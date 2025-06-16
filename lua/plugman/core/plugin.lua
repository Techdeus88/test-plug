---@class PlugmanPlugin
---@field name string
---@field type string
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
    plugin.type = "plugin"
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

---Load the plugin
---@param current_count number The next iter of load_count so a plugin can load and attach itself to the global order
---@return boolean success
---@return string? error
function PlugmanPlugin:load(current_count)
    if self.loaded then
        return true
    end

    if not self.enabled then
        return false, "Plugin is disabled"
    end

    local start_time = vim.loop.hrtime()

    -- Run init hook
    if self.init then
        local ok, err = pcall(self.init)
        if not ok then
            return false, string.format("Init hook failed: %s", err)
        end
    end

    -- Setup plugin if opts provided
    if self.config or self.opts then
        -- Handle configuration
        local merged_opts = self:_merge_config()
        local ok, err = pcall(function()
            self:_process_config(merged_opts)
        end)
        if not ok then
            return false, string.format("Config processing failed: %s", err)
        end
    end

    -- Setup keymaps
    if self.keys then
        local ok, err = pcall(function()
            self:_setup_keymaps()
        end)
        if not ok then
            return false, string.format("Keymap setup failed: %s", err)
        end
    end

    -- Run post hook
    if self.post then
        local ok, err = pcall(self.post)
        if not ok then
            return false, string.format("Post hook failed: %s", err)
        end
    end

    self.loaded = true
    self.load_count = current_count
    self.load_time = (vim.loop.hrtime() - start_time) / 1e6 -- Convert to milliseconds
    return true
end

---Process plugin configuration
---@param merged_opts table
---@return boolean success
---@return string? error
function PlugmanPlugin:_process_config(merged_opts)
    if not merged_opts then
        return true
    end

    if type(self.config) == 'function' then
        local ok, err = pcall(self.config, self, merged_opts)
        if not ok then
            return false, string.format("Config function failed: %s", err)
        end
        return true
    elseif type(self.config) == 'boolean' then
        return self.config
    elseif type(self.config) == 'string' then
        local ok, err = pcall(vim.cmd, self.config)
        if not ok then
            return false, string.format("Config command failed: %s", err)
        end
        return true
    elseif self.config == nil and merged_opts then
        local mod_name = self.require or self.name
        local ok, mod = pcall(require, mod_name)
        if not ok then
            return false, string.format("Failed to require module: %s", mod_name)
        end
        if mod.setup then
            local setup_ok, setup_err = pcall(mod.setup, merged_opts)
            if not setup_ok then
                return false, string.format("Module setup failed: %s", setup_err)
            end
        end
        return true
    end

    return true
end

---Setup plugin keymaps
---@return boolean success
---@return string? error
function PlugmanPlugin:_setup_keymaps()
    if not self.keys then
        return true
    end

    local keymaps = type(self.keys) == "function" and self.keys() or self.keys
    if type(keymaps) ~= "table" then
        return false, "Invalid keymaps format"
    end

    for _, keymap in ipairs(keymaps) do
        if type(keymap) ~= "table" then
            return false, string.format("Invalid keymap entry for %s", self.name)
        end

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
        if type(map_mode) ~= "table" then
            map_mode = { map_mode }
        end

        for _, mode in ipairs(map_mode) do
            if type(mode) ~= "string" then
                return false, string.format("Invalid mode for keymap in %s", self.name)
            end

            local lhs = keymap.lhs or keymap[1]
            local rhs = keymap.rhs or keymap[2]

            if not lhs or not rhs then
                return false, string.format("Missing keymap lhs/rhs in %s", self.name)
            end

            local ok, err = pcall(vim.keymap.set, mode, lhs, rhs, opts)
            if not ok then
                return false, string.format("Failed to set keymap: %s", err)
            end
        end
    end

    return true
end

function PlugmanPlugin:is_installed()
    -- Plugin Management
    local path = self:_build_path()
    return vim.fn.isdirectory(path) == 1
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
