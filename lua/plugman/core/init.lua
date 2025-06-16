---@class PlugmanCore
---@field Utils PlugmanUtils
---@field Dependency PlugmanDependency
---@field Loader PlugmanLoader
---@field Plugin PlugmanPlugin
---@field Cache PlugmanCache
local M = {}

-- Export all core modules
M.Events = require("plugman.core.events")
M.Plugin = require('plugman.core.plugin')
M.Loader = require('plugman.core.loader')
M.Cache = require('plugman.core.cache')
M.Dependency = require('plugman.core.dependency')
M.Utils = require('plugman.core.utils')

return M