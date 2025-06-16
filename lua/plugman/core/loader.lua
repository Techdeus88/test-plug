---@class PlugmanLoader
---@field config PlugmanConfig
---@field events PlugmanEvents
---@field load_order number starts at zero to n
---@field loaded_plugins table<string, PlugmanPlugin>
---@field lazy_handlers table<string, function>
local PlugmanLoader = {}
PlugmanLoader.__index = PlugmanLoader

---Create new loader instance
---@return PlugmanLoader
---@param config PlugmanConfig
function PlugmanLoader:new(config)
  local loader = setmetatable({}, self)
  loader.config = config
  loader.loaded_plugins = {}
  loader.lazy_handlers = {}
  loader.load_order = 0
  loader.events = require('plugman.core.events').new(loader)
  return loader
end

---Load all plugins with proper ordering
---@param plugins table<string, PlugmanPlugin>
function PlugmanLoader:load_all(plugins)
  local start_time = vim.loop.hrtime()

  -- Separate plugins by loading strategy
  local priority_plugins = {}
  local immediate_plugins = {}
  local lazy_plugins = {}

  for _, plugin in pairs(plugins) do
    if plugin.priority > 50 then
      table.insert(priority_plugins, plugin)
    elseif not plugin.lazy then
      table.insert(immediate_plugins, plugin)
    else
      table.insert(lazy_plugins, plugin)
    end
  end

  -- Sort priority plugins by priority (higher first)
  table.sort(priority_plugins, function(a, b)
    return a.priority > b.priority
  end)

  -- Load priority plugins
  for _, plugin in ipairs(priority_plugins) do
    self:_load_plugin(plugin)
  end

  -- Load immediate plugins
  for _, plugin in ipairs(immediate_plugins) do
    self:_load_plugin(plugin)
  end

  -- Setup lazy loading for lazy plugins
  for _, plugin in ipairs(lazy_plugins) do
    self:_setup_lazy_loading(plugin)
  end

  -- Schedule lazy plugins to load after timeout
  vim.defer_fn(function()
    for _, plugin in ipairs(lazy_plugins) do
      if not plugin.loaded and plugin:should_load() then
        self:_load_plugin(plugin)
      end
    end
  end, self.config.lazy_timeout)

  local total_time = (vim.loop.hrtime() - start_time) / 1e6
  vim.notify(string.format('Plugman: Loaded %d plugins in %.2fms',
    #priority_plugins + #immediate_plugins, total_time), vim.log.levels.INFO)
end

---Load a single plugin
---@param plugin PlugmanPlugin
function PlugmanLoader:_load_plugin(plugin)
  if not plugin:should_load() then
    return
  end
  local next_count = self.load_order + 1

  -- Emit loading start event
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'PlugmanPluginLoading',
    data = { name = plugin.name }
  })
  -- local install_ok = plugin:install()
  local load_ok = plugin:load(next_count)

  if load_ok then
    self.loaded_plugins[plugin.name] = plugin

    -- Emit loaded event with timing info
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'PlugmanPluginLoaded',
      data = { name = plugin.name }
    })
  else
    -- Emit error event
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'PlugmanPluginError',
      data = { name = plugin.name, error = plugin.error }
    })
    vim.notify(string.format('Failed to load %s: %s', plugin.name, plugin.error),
      vim.log.levels.ERROR)
  end

  self.load_order = next_count
  return load_ok
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
