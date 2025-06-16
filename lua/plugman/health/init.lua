local M = {}

---Check all plugin health
function M.check_all()
  local plugman = require('plugman')
  local issues = {}
  
  for name, plugin in pairs(plugman.plugins) do
    local plugin_issues = M.check_plugin(plugin)
    if #plugin_issues > 0 then
      issues[name] = plugin_issues
    end
  end
  
  if next(issues) then
    M._report_issues(issues)
  end
end

---Check individual plugin health
---@param plugin PlugmanPlugin
---@return table
function M.check_plugin(plugin)
  local issues = {}
  
  -- Check if plugin is loadable
  if plugin.enabled and not plugin.loaded and not plugin.lazy then
    table.insert(issues, 'Plugin should be loaded but is not')
  end
  
  -- Check dependencies
  for _, dep in ipairs(plugin.depends) do
    local dep_plugin = require('plugman').plugins[dep]
    if not dep_plugin then
      table.insert(issues, 'Missing dependency: ' .. dep)
    elseif not dep_plugin.loaded then
      table.insert(issues, 'Dependency not loaded: ' .. dep)
    end
  end
  
  -- Check for errors
  if plugin.error then
    table.insert(issues, 'Load error: ' .. plugin.error)
  end
  
  return issues
end

---Generate health report
function M.report()
  local report_lines = {}
  table.insert(report_lines, '# Plugman Health Report')
  table.insert(report_lines, '')
  
  local plugman = require('plugman')
  local stats = plugman.api:stats()
  
  table.insert(report_lines, '## Statistics')
  table.insert(report_lines, string.format('- Total plugins: %d', stats.total))
  table.insert(report_lines, string.format('- Loaded plugins: %d', stats.loaded))
  table.insert(report_lines, string.format('- Lazy plugins: %d', stats.lazy))
  table.insert(report_lines, string.format('- Disabled plugins: %d', stats.disabled))
  table.insert(report_lines, string.format('- Plugins with errors: %d', stats.errors))
  table.insert(report_lines, string.format('- Total load time: %.2fms', stats.total_load_time))
  table.insert(report_lines, '')
  
  -- Individual plugin status
  table.insert(report_lines, '## Plugin Status')
  for name, plugin in pairs(plugman.plugins) do
    local status = plugin:status()
    table.insert(report_lines, string.format('- %s: %s', name, status))
    if plugin.error then
      table.insert(report_lines, string.format('  Error: %s', plugin.error))
    end
  end
  
  -- Create health report buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, report_lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  vim.cmd('split')
  vim.api.nvim_win_set_buf(0, buf)
end

---Report health issues
---@param issues table
function M._report_issues(issues)
  local messages = {}
  for name, plugin_issues in pairs(issues) do
    table.insert(messages, string.format('%s: %s', name, table.concat(plugin_issues, ', ')))
  end
  
  vim.notify('Plugman health issues found:\n' .. table.concat(messages, '\n'), 
    vim.log.levels.WARN)
end

return M