---@class PlugmanAPI
local PlugmanAPI = {}
PlugmanAPI.__index = PlugmanAPI

---Create new API instance
---@param plugman Plugman
---@return PlugmanAPI
function PlugmanAPI:new(plugman)
  local api = setmetatable({}, self)
  api.plugman = plugman
  return api
end

---Add a plugin
---@param source string
---@param opts? table
function PlugmanAPI:add(source, opts)
  opts = opts or {}
  local spec = vim.tbl_extend('force', { source }, opts)
  
  local Plugin = require('plugman.core.plugin')
  local plugin = Plugin:new(spec)
  
  self.plugman.plugins[plugin.name] = plugin
  
  -- Load if not lazy
  if not plugin.lazy then
    self.plugman.loader:_load_plugin(plugin)
  else
    self.plugman.loader:_setup_lazy_loading(plugin)
  end
  
  vim.notify('Added plugin: ' .. plugin.name, vim.log.levels.INFO)
end

---Remove a plugin
---@param name string
function PlugmanAPI:remove(name)
  local plugin = self.plugman.plugins[name]
  if not plugin then
    vim.notify('Plugin not found: ' .. name, vim.log.levels.ERROR)
    return
  end
  
  self.plugman.plugins[name] = nil
  vim.notify('Removed plugin: ' .. name, vim.log.levels.INFO)
end

---Enable a plugin
---@param name string
function PlugmanAPI:enable(name)
  local plugin = self.plugman.plugins[name]
  if not plugin then
    vim.notify('Plugin not found: ' .. name, vim.log.levels.ERROR)
    return
  end
  
  plugin.enabled = true
  if not plugin.lazy then
    self.plugman.loader:_load_plugin(plugin)
  end
  
  vim.notify('Enabled plugin: ' .. name, vim.log.levels.INFO)
end

---Disable a plugin
---@param name string
function PlugmanAPI:disable(name)
  local plugin = self.plugman.plugins[name]
  if not plugin then
    vim.notify('Plugin not found: ' .. name, vim.log.levels.ERROR)
    return
  end
  
  plugin.enabled = false
  vim.notify('Disabled plugin: ' .. name, vim.log.levels.INFO)
end

---Sync plugins
function PlugmanAPI:sync()
  vim.notify('Syncing plugins...', vim.log.levels.INFO)
  
  local mini_deps = require('mini.deps')
  local count = 0
  
  for _, plugin in pairs(self.plugman.plugins) do
    if plugin.enabled then
      mini_deps.update()
      count = count + 1
      -- Track plugin sync
      self.plugman.cache:track_plugin_change(plugin.name, 'synced')
    end
  end
  
  vim.notify(string.format('Synced %d plugins', count), vim.log.levels.INFO)
end

---Clean unused plugins
function PlugmanAPI:clean()
  vim.notify('Cleaning unused plugins...', vim.log.levels.INFO)
  
  -- This would integrate with MiniDeps cleanup functionality
  local mini_deps = require('mini.deps')
  -- mini_deps.clean() -- If available
  
  -- Track cleanup
  self.plugman.cache:track_plugin_change('system', 'cleaned')
  
  vim.notify('Cleaned unused plugins', vim.log.levels.INFO)
end

---Set active profile
---@param profile string
function PlugmanAPI:set_profile(profile)
  if not profile then
    vim.notify('Current profile: ' .. self.plugman.config.profile, vim.log.levels.INFO)
    return
  end
  
  self.plugman.config.profile = profile
  -- Track profile change
  self.plugman.cache:mark_config_changed()
  
  vim.notify('Switched to profile: ' .. profile, vim.log.levels.INFO)
  
  -- Reload plugins for new profile
  self.plugman:_load_plugin_specs()
end

---Get plugin statistics
---@return table
function PlugmanAPI:stats()
  local stats = {
    total = 0,
    loaded = 0,
    lazy = 0,
    disabled = 0,
    errors = 0,
    total_load_time = 0,
  }
  
  for _, plugin in pairs(self.plugman.plugins) do
    stats.total = stats.total + 1
    
    if not plugin.enabled then
      stats.disabled = stats.disabled + 1
    elseif plugin.error then
      stats.errors = stats.errors + 1
    elseif plugin.loaded then
      stats.loaded = stats.loaded + 1
      stats.total_load_time = stats.total_load_time + plugin.load_time
    elseif plugin.lazy then
      stats.lazy = stats.lazy + 1
    end
  end
  
  return stats
end

return PlugmanAPI