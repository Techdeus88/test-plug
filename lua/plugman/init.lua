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
    M._scan_directory(M.config.plugins_dir, specs)

    -- Convert specs to PlugmanPlugin objects
    for _, spec in ipairs(specs) do
        M._process_spec(spec)
    end

    -- Sort and load plugins
    M.loader:load_all(M.plugins)
end

---Recursively scan directory for plugin specs
---@param chosen_dir string
---@param specs table
function M._scan_directory(chosen_dir, specs)
    local plugins_dir = { chosen_dir }

    for _, dir in ipairs(plugins_dir) do
        local full_path = vim.fn.stdpath('config') .. '/lua/' .. dir:gsub('%.', '/')
        if vim.fn.isdirectory(full_path) == 1 then
            local files = vim.fn.glob(full_path .. '/*.lua', false, true)
            for _, file in ipairs(files) do
                local filename = vim.fn.fnamemodify(file, ':t:r')
                local module_name = dir .. '.' .. filename

                local ok, plugins_spec = pcall(require, module_name)
                if ok then
                    if type(plugins_spec[1]) == "string" then
                        local spec = plugins_spec
                        table.insert(specs, spec)
                    else
                        for _, spec in ipairs(plugins_spec) do
                            if type(spec) == "table" and type(spec[1]) == "string" then
                                table.insert(specs, spec)
                            end
                        end
                    end
                else
                    vim.notify("Failed to load plugin spec from: " .. module_name, vim.log.levels.ERROR)
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
    -- Main Plugman command
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

    -- Convenience commands
    vim.api.nvim_create_user_command('PlugmanUI', function()
        M.ui:open()
    end, {})

    vim.api.nvim_create_user_command('PlugmanSync', function()
        M.api:sync()
    end, {})

    vim.api.nvim_create_user_command('PlugmanClean', function()
        M.api:clean()
    end, {})

    -- Setup keymaps
    local function setup_keymaps()
        -- Toggle Plugman UI
        vim.keymap.set('n', '<leader>pm', function()
            M.ui:open()
        end, { desc = 'Toggle Plugman UI' })

        -- Quick access keymaps
        vim.keymap.set('n', '<leader>ps', function()
            M.api:sync()
        end, { desc = 'Sync Plugins' })

        vim.keymap.set('n', '<leader>pc', function()
            M.api:clean()
        end, { desc = 'Clean Plugins' })

        vim.keymap.set('n', '<leader>ph', function()
            health.report()
        end, { desc = 'Plugin Health Check' })
    end

    -- Setup keymaps if not in a special mode
    if vim.g.plugman_setup_keymaps ~= false then
        setup_keymaps()
    end
end

return M
