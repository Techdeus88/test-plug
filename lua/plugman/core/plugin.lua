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
---@field post function
---@field installed boolean
---@field added boolean
---@field enabled boolean
---@field loaded boolean
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
    plugin.source = spec[1] or spec.source
    if not plugin.source then
        error('Plugin source is required')
    end

    -- Extract name from source
    plugin.name = spec.name or plugin:_extract_name(plugin.source)

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
    local name = source:match('([^/]+)$')
    if name:match('%.git$') then
        name = name:sub(1, -5)
    end
    return name
end

function PlugmanPlugin:_build_path()
    local base_path = vim.fn.stdpath("data") .. "/site/pack/deps/"
    local start_or_opt = (self.name == "mini.deps" or self.name == "plugman.nvim") and "start" or "opt"
    local plugin_name_path = string.format("/%s", self.name)
    return base_path .. start_or_opt .. plugin_name_path
end

---Check if plugin should be loaded
---@return boolean
function PlugmanPlugin:should_load()
    return self.enabled and not self.loaded
end

---Load the plugin
function PlugmanPlugin:load()
    if self.loaded or not self.enabled then
        return true
    end

    local start_time = vim.loop.hrtime()

    -- Run init hook
    if self.init then
        local ok, err = pcall(self.init)
        if not ok then
            self.error = 'Init failed: ' .. err
            return false
        end
    end

    -- Add to MiniDeps
    local mini_deps = require('mini.deps')
    local ok, err = pcall(mini_deps.add, {
        source = self.source,
        depends = self.depends,
    })

    if not ok then
        self.error = 'MiniDeps failed: ' .. err
        return false
    end

    self.installed = self:is_installed()
    self.added = true

    -- Setup plugin if opts provided
    if next(self.opts) and type(self.opts.setup) ~= 'function' then
        local plugin_module = require(self.name)
        if plugin_module and plugin_module.setup then
            local setup_ok, setup_err = pcall(plugin_module.setup, self.opts)
            if not setup_ok then
                self.error = 'Setup failed: ' .. setup_err
                return false
            end
        end
    elseif type(self.opts.setup) == 'function' then
        local setup_ok, setup_err = pcall(self.opts.setup)
        if not setup_ok then
            self.error = 'Custom setup failed: ' .. setup_err
            return false
        end
    end

    -- Setup keymaps
    self:_setup_keymaps()

    -- Run post hook
    if self.post then
        local ok, err = pcall(self.post)
        if not ok then
            self.error = 'Post hook failed: ' .. err
            return false
        end
    end

    self.loaded = true
    self.load_time = (vim.loop.hrtime() - start_time) / 1e6 -- Convert to milliseconds

    return true
end

function PlugmanPlugin:is_installed()
    -- Plugin Management
    local path = self:_build_path()
    return vim.fn.isdirectory(path) == 1
end

---Setup plugin keymaps
function PlugmanPlugin:_setup_keymaps()
    for _, keymap in ipairs(self.keys) do
        if type(keymap) == "table" and keymap[1] then
            local opts = {
                buffer = keymap.buffer,
                desc = keymap.desc,
                silent = keymap.silent ~= false,
                remap = keymap.remap,
                noremap = keymap.noremap ~= false,
                nowait = keymap.nowait,
                expr = keymap.expr,
            }
            for _, mode in ipairs(keymap.mode or { "n" }) do
                vim.keymap.set(mode, keymap[1], keymap[2], opts)
            end
        else
            logger.warn(string.format("Invalid keymap entry for %s", self.name))
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
