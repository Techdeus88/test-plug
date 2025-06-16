---@class PlugmanCache
---@field config PlugmanConfig
---@field cache_file string
---@field data table
local PlugmanCache = {}
PlugmanCache.__index = PlugmanCache

-- Maximum cache size in bytes
local MAX_CACHE_SIZE = 1024 * 1024 -- 1MB

-- Maximum number of entries
local MAX_ENTRIES = 1000

-- Maximum string length
local MAX_STRING_LENGTH = 10000

---Sanitize value for JSON storage
---@param value any
---@return any
local function sanitize_value(value)
    if type(value) == 'string' then
        -- Truncate long strings
        if #value > MAX_STRING_LENGTH then
            return value:sub(1, MAX_STRING_LENGTH) .. '...'
        end
        return value
    elseif type(value) == 'table' then
        local result = {}
        local count = 0
        for k, v in pairs(value) do
            if count >= MAX_ENTRIES then
                break
            end
            result[k] = sanitize_value(v)
            count = count + 1
        end
        return result
    elseif type(value) == 'number' or type(value) == 'boolean' then
        return value
    else
        return tostring(value)
    end
end

---Pretty print table for JSON
---@param tbl table
---@return string
local function pretty_print_table(tbl)
    local result = {}
    local indent = 0
    local indent_str = '  '

    local function add_indent()
        return string.rep(indent_str, indent)
    end

    local function format_value(v)
        if type(v) == 'table' then
            indent = indent + 1
            local table_str = pretty_print_table(v)
            indent = indent - 1
            return table_str
        elseif type(v) == 'string' then
            return string.format('"%s"', v:gsub('"', '\\"'))
        else
            return tostring(v)
        end
    end

    table.insert(result, '{\n')
    indent = indent + 1

    local count = 0
    for k, v in pairs(tbl) do
        if count >= MAX_ENTRIES then
            table.insert(result, add_indent() .. '...\n')
            break
        end
        table.insert(result, string.format('%s"%s": %s,\n', 
            add_indent(), tostring(k), format_value(v)))
        count = count + 1
    end

    indent = indent - 1
    table.insert(result, add_indent() .. '}')
    return table.concat(result)
end

---Create new cache instance
---@param config PlugmanConfig
---@return PlugmanCache
function PlugmanCache:new(config)
  local cache = setmetatable({}, self)
  cache.config = config
  cache.cache_file = vim.fn.stdpath('cache') .. '/plugman/cache.json'
  cache.data = {}
  
  if config.cache_enabled then
    cache:_load()
  end
  
  return cache
end

---Load cache from file
function PlugmanCache:_load()
  local ok, data = pcall(vim.fn.readfile, self.cache_file)
  if ok and data then
    local success, decoded = pcall(vim.fn.json_decode, data[1])
    if success and type(decoded) == 'table' then
      self.data = decoded
    else
      -- If JSON decode fails, start with empty cache
      self.data = {}
    end
  end
end

---Save cache to file
function PlugmanCache:_save()
  if not self.config.cache_enabled then
    return
  end
  
  -- Sanitize data before saving
  local sanitized_data = sanitize_value(self.data)
  
  -- Check cache size
  local json_str = pretty_print_table(sanitized_data)
  if #json_str > MAX_CACHE_SIZE then
    -- If too large, keep only essential data
    self.data = {
      initialized = self.data.initialized,
      recent_changes = self.data.recent_changes,
      config_changed = self.data.config_changed
    }
    json_str = pretty_print_table(self.data)
  end

  vim.fn.mkdir(vim.fn.stdpath('cache') .. '/plugman', 'p')
  
  -- Write with error handling
  local ok, err = pcall(vim.fn.writefile, {json_str}, self.cache_file)
  if not ok then
    vim.notify('Failed to write cache file: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

---Get cached value
---@param key string
---@return any
function PlugmanCache:get(key)
  if type(key) ~= 'string' then
    return nil
  end
  return self.data[key]
end

---Set cached value
---@param key string
---@param value any
function PlugmanCache:set(key, value)
  if type(key) ~= 'string' then
    return
  end
  self.data[key] = value
  self:_save()
end

---Track plugin changes
---@param plugin_name string
---@param change_type string
function PlugmanCache:track_plugin_change(plugin_name, change_type)
  if type(plugin_name) ~= 'string' or type(change_type) ~= 'string' then
    return
  end

  local changes = self:get('recent_changes') or {}
  table.insert(changes, {
    name = plugin_name,
    type = change_type,
    time = os.time()
  })
  
  -- Keep only last 10 changes
  while #changes > 10 do
    table.remove(changes, 1)
  end
  
  self:set('recent_changes', changes)
end

---Mark configuration as changed
function PlugmanCache:mark_config_changed()
  self:set('config_changed', true)
end

---Clear recent changes
function PlugmanCache:clear_recent_changes()
  self:set('recent_changes', {})
end

---Clear cache
function PlugmanCache:clear()
  self.data = {}
  vim.fn.delete(self.cache_file)
end

return PlugmanCache