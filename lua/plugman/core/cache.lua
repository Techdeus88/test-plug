---@class PlugmanCache
---@field config PlugmanConfig
---@field cache_file string
---@field data table
local PlugmanCache = {}
PlugmanCache.__index = PlugmanCache

---Create new cache instance
---@param config PlugmanConfig
---@return PlugmanCache
function PlugmanCache:new(config)
  local cache = setmetatable({}, self)
  cache.config = config
  cache.cache_file = vim.fn.stdpath('cache') .. '/plugman_cache.lua'
  cache.data = {}
  
  if config.cache_enabled then
    cache:load()
  end
  
  return cache
end

---Load cache from file
function PlugmanCache:load()
  local ok, data = pcall(dofile, self.cache_file)
  if ok and type(data) == 'table' then
    self.data = data
  end
end

---Save cache to file
function PlugmanCache:save()
  if not self.config.cache_enabled then
    return
  end
  
  local cache_dir = vim.fn.fnamemodify(self.cache_file, ':h')
  vim.fn.mkdir(cache_dir, 'p')
  
  local content = 'return ' .. vim.inspect(self.data)
  local file = io.open(self.cache_file, 'w')
  if file then
    file:write(content)
    file:close()
  end
end

---Get cached value
---@param key string
---@return any
function PlugmanCache:get(key)
  return self.data[key]
end

---Set cached value
---@param key string
---@param value any
function PlugmanCache:set(key, value)
  self.data[key] = value
  self:save()
end

---Clear cache
function PlugmanCache:clear()
  self.data = {}
  vim.fn.delete(self.cache_file)
end

return PlugmanCache