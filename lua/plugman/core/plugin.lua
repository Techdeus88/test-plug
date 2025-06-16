---@class PlugmanPlugin
---@field name string
---@field source string
---@field monitor string
---@field checkout string
---@field depends table
---@field hooks table
---@field path string
---@field opts table
---@field lazy boolean
---@field priority number
---@field event table
---@field cmd table
---@field ft table
---@field keys table
---@field init function
---@field config function
---@field require string|nil
---@field post function
---@field installed boolean
---@field added boolean
---@field enabled boolean
---@field loaded boolean
---@field load_count number
---@field load_time number
---@field error nil|string
local PlugmanPlugin = {}
PlugmanPlugin.__index = PlugmanPlugin

---Create new plugin instance
---@param spec table|string
---@return PlugmanPlugin
function PlugmanPlugin:new(spec)
    if type(spec) == 'string' then
        spec = { spec }
    end

    local plugin = setmetatable({}, self)

    -- Parse source
    local source = spec[1] or spec.source
    plugin.source = source
    if not plugin.source then
        error('Plugin source is required')
    end

    -- Extract name from source
    plugin.name = spec.name or plugin:_extract_name(source)

    -- Core properties
    plugin.opts = spec.opts or spec.config or {}
    plugin.lazy = spec.lazy
    plugin.priority = spec.priority or 50
    plugin.depends = spec.depends or spec.dependencies or {}
    plugin.enabled = spec.enabled ~= false

    -- Lazy loading triggers
    plugin.event = spec.event and (type(spec.event) == 'table' and spec.event or { spec.event }) or {}
    plugin.cmd = spec.cmd and (type(spec.cmd) == 'table' and spec.cmd or { spec.cmd }) or {}
    plugin.ft = spec.ft and (type(spec.ft) == 'table' and spec.ft or { spec.ft }) or {}
    plugin.keys = spec.keys or {}

    -- Hooks
    plugin.init = spec.init
    plugin.config = spec.config
    plugin.post = spec.post
    plugin.hooks = spec.hooks

    -- State
    plugin.installed = false
    plugin.added = false
    plugin.loaded = false
    plugin.load_time = 0
    plugin.error = nil

    -- Auto-determine lazy loading
    if plugin.lazy == nil then
        plugin.lazy = #plugin.event > 0 or #plugin.cmd > 0 or #plugin.ft > 0 or #plugin.keys > 0
    end

    return plugin
end

---Extract plugin name from source
---@param source string
---@return string
function PlugmanPlugin:_extract_name(source)
    if not source or type(source) ~= 'string' then
        error('Invalid plugin source: ' .. tostring(source))
    end

    -- Handle different source formats
    local name = source

    -- Remove .git suffix if present
    if name:match('%.git$') then
        name = name:sub(1, -5)
    end

    -- Extract last part of path
    local last_part = name:match('([^/]+)$')
    if last_part then
        name = last_part
    end

    -- Remove any remaining .git suffix
    if name:match('%.git$') then
        name = name:sub(1, -5)
    end

    if not name or name == '' then
        error('Could not extract plugin name from source: ' .. source)
    end

    return name
end

function PlugmanPlugin:_build_path()
    local base_path = vim.fn.stdpath("data") .. "/site/pack/deps/"
    local start_or_opt = (self.name == "mini.deps" or self.name == "plugman.nvim") and "start" or "opt"
    local plugin_name_path = string.format("/%s", self.name)
    return base_path .. start_or_opt .. plugin_name_path
end

---Install plugin
---@return boolean Success
function PlugmanPlugin:install()
    if self.added then
        return true
    end

    local ok, _ = Add({
        source = self.source,
        depends = self.depends,
        hooks = self.hooks,
        checkout = self.checkout,
        monitor = self.monitor,
    })
    if not ok then
        self.error = 'MiniDeps failed: ' .. self.name
        return false
    end

    if ok then
        self.installed = self:is_installed()
        self.added = true
        -- self.cache:set_plugin(self.name, self:to_cache())
        return true
    else
        return false
    end
end

---Check if plugin should be loaded
---@return boolean
function PlugmanPlugin:should_load()
    return self.enabled and not self.loaded
end

-- Configuration Functions
function PlugmanPlugin:_merge_config()
    if not (self.config or self.opts) then return {} end

    local default_opts = type(self.opts) == 'table' and self.opts or {}
    local config_opts = type(self.config) == 'table' and self.config or {}

    return vim.tbl_deep_extend('force', default_opts, config_opts)
end

function PlugmanPlugin:_process_config(merged_opts)
    if not self then return end

    if type(self.config) == 'function' then
        return self.config(self, merged_opts)
    elseif type(self.config) == 'boolean' then
        return self.config
    elseif type(self.config) == 'string' then
        return vim.cmd(self.config)
    elseif merged_opts then
        local mod_name = self.require or self.name
        local ok, mod = pcall(require, mod_name)
        if ok and mod.setup then
            return mod.setup(merged_opts)
        else
            vim.notify(string.format('Failed to require plugin: %s', mod_name))
        end
    end
end

---Load the plugin
---@param load_count number The next iter of load_count so a plugin can load and attach itself to the global order
function PlugmanPlugin:load(current_count)
    if self.loaded or not self.enabled then
        return true
    end

    local start_time = vim.loop.hrtime()

    if not self.added then
        vim.notify(string.format("Installing %s", self.name))
        if not self:install() then
            return false
        end
    end

    if not self.loaded then
        vim.notify(string.format("Loading %s", self.name))
        -- Run init hook
        if self.init then
            local ok, err = pcall(self.init)
            if not ok then
                self.error = 'Init failed: ' .. err
                return false
            end
        end

        -- Setup plugin if opts provided
        if self.config then
            -- Handle configuration
            local merged_opts = self:_merge_config()
            local setup_ok, setup_err = pcall(self._process_config, self, merged_opts)
            if not setup_ok then
                self.error = 'Setup failed: ' .. setup_err
                return false
            end
            vim.notify(string.format("Config loaded: ", setup_ok))
        end

        -- Setup keymaps
        if self.keys then
            self:_setup_keymaps()
        end

        -- Run post hook
        if self.post then
            local ok, err = pcall(self.post)
            if not ok then
                self.error = 'Post hook failed: ' .. err
                return false
            end
        end

        self.loaded = `
        self.load_count = current_count
        self.load_time = (vim.loop.hrtime() - start_time) / 1e6 -- Convert to milliseconds
    end
    return true
end

function PlugmanPlugin:is_installed()
    -- Plugin Management
    local path = self:_build_path()
    return vim.fn.isdirectory(path) == 1
end

---Setup plugin keymaps
function PlugmanPlugin:_setup_keymaps()
    local keymaps = type(self.keys) == "function" and self.keys() or self.keys
    for _, keymap in ipairs(keymaps) do
        if type(keymap) == "table" then
            local opts = {
                buffer = keymap.buffer,
                desc = keymap.desc,
                silent = keymap.silent ~= false,
                remap = keymap.remap,
                noremap = keymap.noremap ~= false,
                nowait = keymap.nowait,
                expr = keymap.expr,
            }
            local map_mode = keymap.mode ~= nil and keymap.mode or { "n" }
            for _, mode in ipairs(map_mode) do
                vim.keymap.set(mode, keymap[1], keymap[2], opts)
            end
        else
            vim.notify(string.format("Invalid keymap entry for %s", self.name))
        end
    end
end

---Get plugin status
---@return string
function PlugmanPlugin:status()
    if self.error then
        return 'error'
    elseif self.loaded then
        return 'loaded'
    elseif not self.enabled then
        return 'disabled'
    else
        return 'not_loaded'
    end
end

return PlugmanPlugin
