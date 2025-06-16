---@class Plugman
---@field config PlugmanConfig
---@field plugins table<string, PlugmanPlugin>
---@field cache PlugmanCache
---@field loader PlugmanLoader
---@field ui PlugmanUI
---@field api PlugmanAPI
local M = {}

local config = require('plugman.config')
local core = require('plugman.core')
-- Add near the top after other requires
local logger = require('plugman.logger')
local ui = require('plugman.ui')
local api = require('plugman.api')
local health = require('plugman.health')
local benchmark = require('plugman.benchmark')

M.config = config
M.plugins = {}
M.state = {
    initialized = false,
    loading = false,
    stats = {
        load_time = 0,
        plugin_count = 0,
        loaded_count = 0,
    }
}

---Initialize Plugman
---@param opts? PlugmanConfig
function M.setup(opts)
    M.config = vim.tbl_deep_extend('force', config, opts or {})
    -- Initialize logger
    logger.setup(M.config)
    logger:info('Plugman initialization started')

    -- Initialize MiniDeps
    local path_package = vim.fn.stdpath('data') .. '/site/'
    local mini_path = path_package .. 'pack/deps/start/mini.deps'
    if not vim.loop.fs_stat(mini_path) then
        vim.cmd('echo "Installing `mini.deps`" | redraw')
        local clone_cmd = {
            'git', 'clone', '--filter=blob:none',
            'https://github.com/echasnovski/mini.deps', mini_path
        }
        vim.fn.system(clone_cmd)
        vim.cmd('packadd mini.deps | helptags ALL')
    end

    require('mini.deps').setup({ path = { package = path_package } })

    -- Initialize core components
    M.cache = core.Cache:new(M.config)
    M.loader = core.Loader:new(M.config)
    M.ui = ui:new(M.config)
    M.api = api:new(M)

    -- Load plugins
    M._load_plugin_specs()
    M._setup_autocmds()
    M._setup_commands()

    M.state.initialized = true

    if M.config.performance.benchmark_enabled then
        benchmark.start()
    end
    logger:info('Plugman initialization completed')
end

---Load plugin specifications from configured directory
function M._load_plugin_specs()
    local plugins_path = vim.fn.stdpath('config') .. '/lua/' .. M.config.plugins_dir

    if not vim.loop.fs_stat(plugins_path) then
        vim.notify('Plugman: plugins directory not found: ' .. plugins_path, vim.log.levels.WARN)
        return
    end

    local specs = {}
    M._scan_directory(plugins_path, specs)

    -- Convert specs to PlugmanPlugin objects
    for _, spec in ipairs(specs) do
        M._process_spec(spec)
    end

    -- Sort and load plugins
    M.loader:load_all(M.plugins)
end

---Recursively scan directory for plugin specs
---@param dir string
---@param specs table
function M._scan_directory(dir, specs)
    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end

    while true do
        local name, t_type = vim.loop.fs_scandir_next(handle)
        if not name then break end

        local full_path = dir .. '/' .. name
        if t_type == 'directory' then
            M._scan_directory(full_path, specs)
        elseif t_type == 'file' and name:match('%.lua$') then
            local filename = vim.fn.fnamemodify(name, ':t:r')
            local module_name = dir .. '.' .. filename
            local ok, spec = pcall(require, module_name)
            if ok and spec then
                if type(spec) == 'table' then
                    if type(spec[1]) == "string" then
                        local s = spec
                        table.insert(specs, s)
                      else
                        for _, s in ipairs(spec) do
                          if type(s) == "table" and type(s[1]) == "string" then
                            table.insert(specs, s)
                          end
                        end
                      end
                end
            end
        end
    end
end

---Process a plugin specification
---@param spec table
function M._process_spec(spec)
    local Plugin = require('plugman.core.plugin')
    local plugin = Plugin:new(spec)
    M.plugins[plugin.name] = plugin
end

---Setup autocommands
function M._setup_autocmds()
    local group = vim.api.nvim_create_augroup('Plugman', { clear = true })

    -- Lazy loading triggers
    vim.api.nvim_create_autocmd('User', {
        group = group,
        pattern = 'PlugmanLazyLoad',
        callback = function(ev)
            M.loader:load_lazy_plugin(ev.data.name)
        end,
    })

    -- Health check on VimEnter
    vim.api.nvim_create_autocmd('VimEnter', {
        group = group,
        callback = function()
            vim.defer_fn(function()
                health.check_all()
            end, 100)
        end,
    })
end

---Setup user commands
function M._setup_commands()
    vim.api.nvim_create_user_command('Plugman', function(opts)
        local args = vim.split(opts.args, '%s+')
        local cmd = args[1] or 'ui'

        if cmd == 'ui' then
            M.ui:open()
        elseif cmd == 'sync' then
            M.api:sync()
        elseif cmd == 'clean' then
            M.api:clean()
        elseif cmd == 'health' then
            health.report()
        elseif cmd == 'benchmark' then
            benchmark.report()
        elseif cmd == 'profile' then
            M.api:set_profile(args[2])
        else
            vim.notify('Unknown command: ' .. cmd, vim.log.levels.ERROR)
        end
    end, {
        nargs = '*',
        complete = function()
            return { 'ui', 'sync', 'clean', 'health', 'benchmark', 'profile' }
        end,
    })
end

return M
