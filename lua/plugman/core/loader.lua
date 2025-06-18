---@class PlugmanLoader
---@field config PlugmanConfig
---@field events PlugmanEvents
---@field load_order number starts at zero to n
---@field loaded_plugins table<string, PlugmanPlugin>
---@field lazy_handlers table<string, function>
---@field plugins table<string, PlugmanPlugin>
local PlugmanLoader = {}
PlugmanLoader.__index = PlugmanLoader

---Create new loader instance
---@return PlugmanLoader
---@param plugins table<string, PlugmanPlugin>
---@param config PlugmanConfig
function PlugmanLoader:new(config, plugins)
  ---@class PlugmanLoader
  local loader = setmetatable({}, self)
  loader.config = config
  loader.plugins = plugins
  loader.loaded_plugins = {}
  loader.lazy_handlers = {}
  loader.load_order = 0
  loader.events = require('plugman.core.events').new(loader)
  loader.loading_plugins = {} -- Track plugins being loaded to prevent circular deps
  loader.load_errors = {} -- Track loading errors
  return loader
end

---Resolve plugin dependencies
---@param plugin PlugmanPlugin
---@return boolean success
---@return string? error
function PlugmanLoader:_resolve_dependencies(plugin)
  if not plugin.depends or #plugin.depends == 0 then
    return true
  end

  -- Check for circular dependencies
  if self.loading_plugins[plugin.name] then
    return false, string.format("Circular dependency detected for plugin: %s", plugin.name)
  end

  self.loading_plugins[plugin.name] = true

  for _, dep_source in ipairs(plugin.depends) do
    local dep_name = require("core.utils").get_name_from_source(dep_source)
    local dep = self.plugins[dep_name]
    if not dep then
      return false, string.format("Dependency not found: %s for plugin: %s", dep_name, plugin.name)
    end

    if not dep.loaded then
      local success, err = self:_resolve_dependencies(dep)
      if not success then
        self.loading_plugins[plugin.name] = nil
        return false, err
      end

      success, err = self:_load_plugin(dep)
      if not success then
        self.loading_plugins[plugin.name] = nil
        return false, err
      end
    end
  end

  self.loading_plugins[plugin.name] = nil
  return true
end

---Load all plugins with proper ordering
---@param plugins table<string, PlugmanPlugin>
function PlugmanLoader:load_all(plugins)
  local start_time = vim.loop.hrtime()
  self.load_errors = {} -- Reset errors

  -- Validate plugins table
  if not plugins or type(plugins) ~= 'table' then
    vim.notify('Invalid plugins table provided to load_all', vim.log.levels.ERROR)
    return
  end

  -- Separate plugins by loading strategy
  local priority_plugins = {}
  local immediate_plugins = {}
  local lazy_plugins = {}

  for name, plugin in pairs(plugins) do
    if not plugin or type(plugin) ~= 'table' then
      vim.notify(string.format('Invalid plugin entry for %s', name), vim.log.levels.ERROR)
      goto continue
    end

    if not plugin.name then
      vim.notify(string.format('Plugin missing name: %s', vim.inspect(plugin)), vim.log.levels.ERROR)
      goto continue
    end

    if plugin.priority and plugin.priority > 50 then
      table.insert(priority_plugins, plugin)
    elseif not plugin.lazy then
      table.insert(immediate_plugins, plugin)
    else
      table.insert(lazy_plugins, plugin)
    end

    ::continue::
  end

  -- Sort priority plugins by priority (higher first)
  table.sort(priority_plugins, function(a, b)
    return (a.priority or 0) > (b.priority or 0)
  end)

  -- Load priority plugins
  for _, plugin in ipairs(priority_plugins) do
    local success, err = self:_load_plugin(plugin)
    if not success then
      self.load_errors[plugin.name] = err
      vim.notify(string.format('Failed to load priority plugin %s: %s', plugin.name, err),
        vim.log.levels.ERROR)
    end
  end

  -- Load immediate plugins
  for _, plugin in ipairs(immediate_plugins) do
    local success, err = self:_load_plugin(plugin)
    if not success then
      self.load_errors[plugin.name] = err
      vim.notify(string.format('Failed to load immediate plugin %s: %s', plugin.name, err),
        vim.log.levels.ERROR)
    end
  end

  -- Setup lazy loading for lazy plugins
  for _, plugin in ipairs(lazy_plugins) do
    local success, err = pcall(function()
      self:_setup_lazy_loading(plugin)
    end)
    if not success then
      self.load_errors[plugin.name] = err
      vim.notify(string.format('Failed to setup lazy loading for %s: %s', plugin.name, err),
        vim.log.levels.ERROR)
    end
  end

  local total_time = (vim.loop.hrtime() - start_time) / 1e6
  local loaded_count = #priority_plugins + #immediate_plugins
  local error_count = #vim.tbl_keys(self.load_errors)

  if error_count > 0 then
    vim.notify(string.format('Plugman: Loaded %d plugins in %.2fms (%d errors)',
      loaded_count, total_time, error_count), vim.log.levels.WARN)
  else
    vim.notify(string.format('Plugman: Loaded %d plugins in %.2fms',
      loaded_count, total_time), vim.log.levels.INFO)
  end
end

---Load a single plugin
---@param plugin PlugmanPlugin
---@return boolean success
---@return string? error
function PlugmanLoader:_load_plugin(plugin)
  if not plugin then
    return false, "Invalid plugin object"
  end

  if not plugin.name then
    return false, "Plugin missing name"
  end

  if not plugin:should_load() then
    return true
  end

  -- Resolve dependencies first
  local success, err = self:_resolve_dependencies(plugin)
  if not success then
    return false, string.format("Dependency resolution failed: %s", err)
  end

  local next_count = self.load_order + 1

  -- Emit loading start event
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'PlugmanPluginLoading',
    data = { name = plugin.name }
  })

  -- Ensure plugin is installed
  if not plugin.added then
    local install_ok = plugin:install()
    if not install_ok then
      return false, string.format("Failed to install plugin: %s", plugin.name)
    end
  end

  -- Load the plugin
  local load_ok, load_err = plugin:load(next_count)
  if not load_ok then
    -- Emit error event
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'PlugmanPluginError',
      data = { name = plugin.name, error = load_err }
    })
    return false, load_err
  end

  self.loaded_plugins[plugin.name] = plugin
  self.load_order = next_count

  -- Emit loaded event with timing info
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'PlugmanPluginLoaded',
    data = { name = plugin.name }
  })

  return true
end

---Setup lazy loading for a plugin
---@param plugin PlugmanPlugin
function PlugmanLoader:_setup_lazy_loading(plugin)
  -- Event triggers
  for _, event in ipairs(plugin.event) do
    self:_setup_event_trigger(plugin, event)
  end

  -- Command triggers
  for _, cmd in ipairs(plugin.cmd) do
    self:_setup_command_trigger(plugin, cmd)
  end

  -- Filetype triggers
  for _, ft in ipairs(plugin.ft) do
    self:_setup_filetype_trigger(plugin, ft)
  end

  -- Keymap triggers
  for _, key in ipairs(plugin.keys) do
    self:_setup_keymap_trigger(plugin, key)
  end
end

---Setup event trigger for lazy loading
---@param plugin PlugmanPlugin
---@param event string
function PlugmanLoader:_setup_event_trigger(plugin, event)
  -- Use the Events module to handle the event
  self.events:on_event(event, function()
    self:load_lazy_plugin(plugin.name)
  end, { priority = 100 }) -- High priority to ensure plugin loads before other handlers
end

---Setup command trigger for lazy loading
---@param plugin PlugmanPlugin
---@param cmd string
function PlugmanLoader:_setup_command_trigger(plugin, cmd)
  vim.api.nvim_create_user_command(cmd, function(opts)
    self:load_lazy_plugin(plugin.name)
    -- Re-execute the command after loading
    vim.schedule(function()
      vim.cmd(cmd .. ' ' .. opts.args)
    end)
  end, { nargs = '*', range = true })
end

---Setup filetype trigger for lazy loading
---@param plugin PlugmanPlugin
---@param ft string
function PlugmanLoader:_setup_filetype_trigger(plugin, ft)
  vim.api.nvim_create_autocmd('FileType', {
    pattern = ft,
    group = vim.api.nvim_create_augroup('PlugmanLazyFT_' .. plugin.name, {}),
    once = true,
    callback = function()
      self:load_lazy_plugin(plugin.name)
    end,
  })
end

---Setup keymap trigger for lazy loading
---@param plugin PlugmanPlugin
---@param key table
function PlugmanLoader:_setup_keymap_trigger(plugin, key)
  local modes = type(key.mode) == 'table' and key.mode or { key.mode or 'n' }
  local lhs = key.lhs or key[1]
  local rhs = key.rhs or key[2]

  for _, mode in ipairs(modes) do
    vim.keymap.set(mode, lhs, function()
      self:load_lazy_plugin(plugin.name)
      -- Re-execute the keymap after loading
      vim.schedule(function()
        if type(rhs) == 'string' then
          vim.cmd(rhs)
        elseif type(rhs) == 'function' then
          rhs()
        end
      end)
    end, { desc = key.desc })
  end
end

---Load a lazy plugin by name
---@param name string
function PlugmanLoader:load_lazy_plugin(name)
  local plugman = require('plugman')
  local plugin = plugman.plugins[name]

  if not plugin then
    vim.notify('Plugin not found: ' .. name, vim.log.levels.ERROR)
    return
  end

  if plugin.loaded then
    return
  end

  self:_load_plugin(plugin)
end

return PlugmanLoader
