---@class PlugmanUtils
local M = {}

---Deep merge two tables
---@param target table
---@param source table
---@return table
function M.deep_merge(target, source)
  local result = vim.deepcopy(target)
  
  for key, value in pairs(source) do
    if type(value) == 'table' and type(result[key]) == 'table' then
      result[key] = M.deep_merge(result[key], value)
    else
      result[key] = value
    end
  end
  
  return result
end

---Check if a table is empty
---@param t table
---@return boolean
function M.is_empty(t)
  return next(t) == nil
end

---Convert string or table to table
---@param value string|table
---@return table
function M.ensure_table(value)
  if type(value) == 'string' then
    return { value }
  elseif type(value) == 'table' then
    return value
  else
    return {}
  end
end

---Safely call a function with error handling
---@param fn function
---@param ... any
---@return boolean, any
function M.safe_call(fn, ...)
  local ok, result = pcall(fn, ...)
  return ok, result
end

---Check if a plugin exists in runtime path
---@param name string
---@return boolean
function M.plugin_exists(name)
  local paths = vim.api.nvim_list_runtime_paths()
  for _, path in ipairs(paths) do
    if path:match(name .. '$') then
      return true
    end
  end
  return false
end

---Get plugin directory path
---@param name string
---@return string|nil
function M.get_plugin_path(name)
  local paths = vim.api.nvim_list_runtime_paths()
  for _, path in ipairs(paths) do
    if path:match(name .. '$') then
      return path
    end
  end
  return nil
end

---Parse git URL to extract repository name
---@param url string
---@return string
function M.parse_git_url(url)
  -- Handle different git URL formats
  local patterns = {
    'https://github%.com/[^/]+/([^/%.]+)',  -- https://github.com/user/repo
    'git@github%.com:[^/]+/([^/%.]+)',      -- git@github.com:user/repo
    'https://gitlab%.com/[^/]+/([^/%.]+)',  -- https://gitlab.com/user/repo
    '([^/]+)$'                              -- fallback for simple names
  }
  
  for _, pattern in ipairs(patterns) do
    local match = url:match(pattern)
    if match then
      return match:gsub('%.git$', '') -- Remove .git suffix
    end
  end
  
  return url
end

---Normalize plugin source to full git URL
---@param source string
---@return string
function M.normalize_source(source)
  -- Already a full URL
  if source:match('^https?://') or source:match('^git@') then
    return source
  end
  
  -- GitHub shorthand (user/repo)
  if source:match('^[%w%-_%.]+/[%w%-_%.]+$') then
    return 'https://github.com/' .. source
  end
  
  -- Single name, assume it's on GitHub under some common orgs
  local common_orgs = { 'nvim-lua', 'folke', 'hrsh7th', 'williamboman' }
  for _, org in ipairs(common_orgs) do
    local full_url = 'https://github.com/' .. org .. '/' .. source
    -- In a real implementation, you might want to check if this exists
    -- For now, we'll default to the first match
    return full_url
  end
  
  return source
end

---Create directory if it doesn't exist
---@param path string
---@return boolean
function M.ensure_dir(path)
  local stat = vim.loop.fs_stat(path)
  if not stat then
    return vim.fn.mkdir(path, 'p') == 1
  end
  return stat.type == 'directory'
end

---Read file contents
---@param path string
---@return string|nil
function M.read_file(path)
  local file = io.open(path, 'r')
  if not file then
    return nil
  end
  
  local content = file:read('*all')
  file:close()
  return content
end

---Write content to file
---@param path string
---@param content string
---@return boolean
function M.write_file(path, content)
  local file = io.open(path, 'w')
  if not file then
    return false
  end
  
  file:write(content)
  file:close()
  return true
end

---Get file modification time
---@param path string
---@return number|nil
function M.get_mtime(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.mtime.sec or nil
end

---Check if file is newer than another
---@param file1 string
---@param file2 string
---@return boolean
function M.is_newer(file1, file2)
  local mtime1 = M.get_mtime(file1)
  local mtime2 = M.get_mtime(file2)
  
  if not mtime1 or not mtime2 then
    return false
  end
  
  return mtime1 > mtime2
end

---Debounce function calls
---@param fn function
---@param delay number
---@return function
function M.debounce(fn, delay)
  local timer = nil
  
  return function(...)
    local args = { ... }
    
    if timer then
      timer:stop()
    end
    
    timer = vim.defer_fn(function()
      fn(unpack(args))
      timer = nil
    end, delay)
  end
end

---Throttle function calls
---@param fn function
---@param delay number
---@return function
function M.throttle(fn, delay)
  local last_call = 0
  
  return function(...)
    local now = vim.loop.now()
    if now - last_call >= delay then
      last_call = now
      return fn(...)
    end
  end
end

---Format time duration
---@param ms number
---@return string
function M.format_time(ms)
  if ms < 1 then
    return string.format('%.2fμs', ms * 1000)
  elseif ms < 1000 then
    return string.format('%.2fms', ms)
  else
    return string.format('%.2fs', ms / 1000)
  end
end

---Get human readable file size
---@param bytes number
---@return string
function M.format_size(bytes)
  local units = { 'B', 'KB', 'MB', 'GB', 'TB' }
  local size = bytes
  local unit_index = 1
  
  while size >= 1024 and unit_index < #units do
    size = size / 1024
    unit_index = unit_index + 1
  end
  
  return string.format('%.1f%s', size, units[unit_index])
end

---Check if running on Windows
---@return boolean
function M.is_windows()
  return vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
end

---Check if running on macOS
---@return boolean
function M.is_macos()
  return vim.fn.has('mac') == 1 or vim.fn.has('macunix') == 1
end

---Check if running on Linux
---@return boolean
function M.is_linux()
  return vim.fn.has('unix') == 1 and not M.is_macos()
end

---Get system info
---@return table
function M.get_system_info()
  return {
    os = M.is_windows() and 'windows' or M.is_macos() and 'macos' or 'linux',
    nvim_version = vim.version(),
    has_git = vim.fn.executable('git') == 1,
    has_curl = vim.fn.executable('curl') == 1,
    config_path = vim.fn.stdpath('config'),
    data_path = vim.fn.stdpath('data'),
    cache_path = vim.fn.stdpath('cache'),
  }
end

---Validate plugin specification
---@param spec table
---@return boolean, string?
function M.validate_spec(spec)
  -- Check required fields
  if not spec.source and not spec[1] then
    return false, 'Plugin source is required'
  end
  
  -- Check types
  local type_checks = {
    { 'lazy', 'boolean' },
    { 'priority', 'number' },
    { 'enabled', 'boolean' },
    { 'event', { 'string', 'table' } },
    { 'cmd', { 'string', 'table' } },
    { 'ft', { 'string', 'table' } },
    { 'keys', 'table' },
    { 'depends', 'table' },
    { 'init', 'function' },
    { 'post', 'function' },
  }
  
  for _, check in ipairs(type_checks) do
    local field, expected_type = check[1], check[2]
    local value = spec[field]
    
    if value ~= nil then
      if type(expected_type) == 'table' then
        local valid = false
        for _, t in ipairs(expected_type) do
          if type(value) == t then
            valid = true
            break
          end
        end
        if not valid then
          return false, string.format('Field "%s" must be one of: %s', 
            field, table.concat(expected_type, ', '))
        end
      elseif type(value) ~= expected_type then
        return false, string.format('Field "%s" must be %s', field, expected_type)
      end
    end
  end
  
  return true
end

---Create a simple logger
---@param level string
---@return table
function M.create_logger(level)
  local levels = { 'trace', 'debug', 'info', 'warn', 'error' }
  local level_nums = {}
  for i, l in ipairs(levels) do
    level_nums[l] = i
  end
  
  local current_level = level_nums[level] or level_nums.info
  
  local logger = {}
  
  for i, l in ipairs(levels) do
    logger[l] = function(msg, ...)
      if i >= current_level then
        local formatted = string.format(msg, ...)
        vim.notify(string.format('[Plugman:%s] %s', l:upper(), formatted), 
          vim.log.levels[l:upper()])
      end
    end
  end
  
  return logger
end

---Measure execution time of a function
---@param fn function
---@param ... any
---@return any, number
function M.measure_time(fn, ...)
  local start = vim.loop.hrtime()
  local result = fn(...)
  local duration = (vim.loop.hrtime() - start) / 1e6 -- Convert to milliseconds
  return result, duration
end

---Generate unique ID
---@return string
function M.generate_id()
  local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  local id = ''
  for _ = 1, 8 do
    local rand = math.random(1, #chars)
    id = id .. chars:sub(rand, rand)
  end
  return id
end

---Check if value is in table
---@param table table
---@param value any
---@return boolean
function M.contains(table, value)
  for _, v in ipairs(table) do
    if v == value then
      return true
    end
  end
  return false
end

---Filter table by predicate
---@param table table
---@param predicate function
---@return table
function M.filter(table, predicate)
  local result = {}
  for _, item in ipairs(table) do
    if predicate(item) then
      table.insert(result, item)
    end
  end
  return result
end

---Map table values
---@param table table
---@param mapper function
---@return table
function M.map(table, mapper)
  local result = {}
  for _, item in ipairs(table) do
    table.insert(result, mapper(item))
  end
  return result
end

---Find item in table
---@param table table
---@param predicate function
---@return any
function M.find(table, predicate)
  for _, item in ipairs(table) do
    if predicate(item) then
      return item
    end
  end
  return nil
end

return M