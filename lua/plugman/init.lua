---@class Plugman
---@field Config PlugmanConfig
---@field plugins table<string, PlugmanPlugin>
---@field cache PlugmanCache
---@field loader PlugmanLoader
---@field ui PlugmanUI
---@field api PlugmanAPI
local M = {}

local Config = require('plugman.config')
local core = require('plugman.core')
local logger = require('plugman.logger')
local ui = require('plugman.ui')
local api = require('plugman.api')
local health = require('plugman.health')
local benchmark = require('plugman.benchmark')

M.Config = Config
M.plugins = {}
M.state = {
    initialized = false,
    loading = false,
    stats = {
        load_time = 0,
        plugin_count = 0,
        loaded_count = 0,
    },
}

---Initialize Plugman
---@param opts? PlugmanConfig
function M.setup(opts)
    M.Config = vim.tbl_deep_extend('force', Config, opts or {})
    -- Initialize logger
    logger.setup(M.Config)
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

    local MiniDeps = require('mini.deps')
    MiniDeps.setup({ path = { package = path_package } })
    Add, Now, Later = MiniDeps.add, MiniDeps.now, MiniDeps.later

    -- Initialize core components
    M.cache = core.Cache:new(M.Config)
    M.events = core.Events.new(M.loader)
    M.loader = core.Loader:new(M.Config, M.plugins)
    M.ui = ui:new(M.Config)
    M.api = api:new(M)

    -- Load plugins
    M._load_plugin_specs()
    M._setup_autocmds()
    M._setup_commands()

    M.state.initialized = true

    if M.Config.performance.benchmark_enabled then
        benchmark.start()
    end
    logger:info('Plugman initialization completed')
end

---Load plugin specifications from Configured directory
function M._load_plugin_specs()
    local plugins_path = vim.fn.stdpath('config') .. '/lua/' .. M.Config.plugins_dir

    if not vim.loop.fs_stat(plugins_path) then
        vim.notify('Plugman: plugins directory not found: ' .. plugins_path, vim.log.levels.WARN)
        return
    end

    local specs = {}
    M._scan_directory(M.Config.plugins_dir, specs)

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
    local full_path = vim.fn.stdpath('config') .. '/lua/' .. chosen_dir:gsub('%.', '/')

    if vim.fn.isdirectory(full_path) ~= 1 then
        return
    end

    -- Process all .lua files in current directory
    local files = vim.fn.glob(full_path .. '/*.lua', false, true)
    for _, file in ipairs(files) do
        local filename = vim.fn.fnamemodify(file, ':t:r')
        local module_name = chosen_dir .. '.' .. filename

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

    -- Recursively process subdirectories
    local subdirs = vim.fn.glob(full_path .. '/*/', false, true)
    for _, subdir in ipairs(subdirs) do
        local subdir_name = vim.fn.fnamemodify(subdir, ':t')
        local new_chosen_dir = chosen_dir .. '.' .. subdir_name
        M._scan_directory(new_chosen_dir, specs)
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

    -- Health check and auto-launch dashboard on VimEnter
    vim.api.nvim_create_autocmd('VimEnter', {
        group = group,
        callback = function()
            vim.defer_fn(function()
                -- Run health check
                health.check_all()

                -- Auto-launch dashboard if conditions are met
                local should_auto_launch = false

                -- Condition 1: First time setup
                if not M.cache:get('initialized') then
                    should_auto_launch = true
                    M.cache:set('initialized', true)
                end

                -- Condition 2: Plugins need attention
                local stats = M.api:stats()
                if stats.errors > 0 or stats.disabled > 0 then
                    should_auto_launch = true
                end

                -- Condition 3: Recent plugin changes
                local recent_changes = M.cache:get('recent_changes') or {}
                if #recent_changes > 0 then
                    should_auto_launch = true
                end

                -- Condition 4: Configuration changed
                if M.cache:get('config_changed') then
                    should_auto_launch = true
                    M.cache:set('config_changed', false)
                end

                if should_auto_launch then
                    M.ui:open()
                end
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
        end, { desc = 'Cleans Plugins' })

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
