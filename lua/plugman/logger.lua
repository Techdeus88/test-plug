---@class PlugmanLogger
local PlugmanLogger = {}
PlugmanLogger.__index = PlugmanLogger

local utils = require('plugman.core.utils')

-- Private instance
local _instance = nil

---@class LogEntry
---@field timestamp string
---@field level string
---@field message string
---@field source string?
---@field data any?

---Create new logger instance
---@param config table
---@return PlugmanLogger
function PlugmanLogger:new(config)
    if _instance then
        return _instance
    end

    ---@class PlugmanLogger
    local logger = setmetatable({}, self)

    logger.config = vim.tbl_extend('force', {
        level = 'info',
        file_logging = true,
        console_logging = true,
        max_file_size = 1024 * 1024, -- 1MB
        max_log_files = 5,
        log_dir = vim.fn.stdpath('cache') .. '/plugman',
        date_format = '%Y-%m-%d %H:%M:%S',
        buffer_size = 1000,
        auto_flush = true,
        flush_interval = 5000, -- 5 seconds
    }, config or {})

    logger.levels = {
        trace = 0,
        debug = 1,
        info = 2,
        warn = 3,
        error = 4,
        fatal = 5,
    }

    logger.level_names = { 'trace', 'debug', 'info', 'warn', 'error', 'fatal' }
    logger.current_level = logger.levels[logger.config.level] or logger.levels.info

    -- In-memory buffer for recent logs
    logger.buffer = {}
    logger.buffer_index = 1

    -- File handles
    logger.log_file = nil
    logger.log_file_path = nil

    -- Flush timer
    logger.flush_timer = nil

    -- Initialize
    logger:_init()

    _instance = logger
    return logger
end

---Initialize logger
function PlugmanLogger:_init()
    -- Ensure log directory exists
    if self.config.file_logging then
        utils.ensure_dir(self.config.log_dir)
        self:_setup_log_file()
    end

    -- Setup auto-flush timer
    if self.config.auto_flush then
        self:_setup_flush_timer()
    end

    -- Setup cleanup autocmd
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = vim.api.nvim_create_augroup('PlugmanLogger', { clear = true }),
        callback = function()
            self:flush()
            self:close()
        end,
    })
end

---Setup log file
function PlugmanLogger:_setup_log_file()
    local timestamp = os.date('%Y%m%d')
    self.log_file_path = string.format('%s/plugman_%s.log', self.config.log_dir, timestamp)

    -- Rotate logs if needed
    self:_rotate_logs()

    -- Open log file
    self.log_file = io.open(self.log_file_path, 'a')
    if not self.log_file then
        vim.notify('Plugman Logger: Failed to open log file: ' .. self.log_file_path, vim.log.levels.WARN)
        self.config.file_logging = false
    end
end

---Rotate log files
function PlugmanLogger:_rotate_logs()
    -- Check current log file size
    local stat = vim.loop.fs_stat(self.log_file_path)
    if stat and stat.size > self.config.max_file_size then
        -- Close current file
        if self.log_file then
            self.log_file:close()
        end

        -- Rotate files
        for i = self.config.max_log_files - 1, 1, -1 do
            local old_file = string.format('%s.%d', self.log_file_path, i)
            local new_file = string.format('%s.%d', self.log_file_path, i + 1)

            if vim.loop.fs_stat(old_file) then
                os.rename(old_file, new_file)
            end
        end

        -- Move current to .1
        if vim.loop.fs_stat(self.log_file_path) then
            os.rename(self.log_file_path, self.log_file_path .. '.1')
        end
    end

    -- Clean up old log files
    for i = self.config.max_log_files + 1, self.config.max_log_files + 10 do
        local old_file = string.format('%s.%d', self.log_file_path, i)
        if vim.loop.fs_stat(old_file) then
            os.remove(old_file)
        end
    end
end

---Setup flush timer
function PlugmanLogger:_setup_flush_timer()
    if self.flush_timer then
        self.flush_timer:stop()
    end

    self.flush_timer = vim.loop.new_timer()
    self.flush_timer:start(self.config.flush_interval, self.config.flush_interval, vim.schedule_wrap(function()
        self:flush()
    end))
end

---Log a message
---@param level string
---@param message string
---@param source string?
---@param data any?
function PlugmanLogger:log(level, message, source, data)
    local level_num = self.levels[level]
    if not level_num or level_num < self.current_level then
        return
    end

    local entry = {
        timestamp = os.date(self.config.date_format),
        level = level,
        message = message,
        source = source,
        data = data,
    }

    -- Add to buffer
    self:_add_to_buffer(entry)

    -- Console logging
    if self.config.console_logging then
        self:_log_to_console(entry)
    end

    -- File logging
    if self.config.file_logging and self.log_file then
        self:_log_to_file(entry)
    end

    -- Auto flush if needed
    if self.config.auto_flush then
        self:flush()
    end
end

---Add entry to buffer
---@param entry LogEntry
function PlugmanLogger:_add_to_buffer(entry)
    self.buffer[self.buffer_index] = entry
    self.buffer_index = self.buffer_index + 1

    if self.buffer_index > self.config.buffer_size then
        self.buffer_index = 1
    end
end

---Log to console
---@param entry LogEntry
function PlugmanLogger:_log_to_console(entry)
    local level_colors = {
        trace = vim.log.levels.TRACE,
        debug = vim.log.levels.DEBUG,
        info = vim.log.levels.INFO,
        warn = vim.log.levels.WARN,
        error = vim.log.levels.ERROR,
        fatal = vim.log.levels.ERROR,
    }

    local prefix = string.format('[Plugman:%s]', entry.level:upper())
    local message = entry.source and string.format('%s [%s] %s', prefix, entry.source, entry.message)
        or string.format('%s %s', prefix, entry.message)

    vim.notify(message, level_colors[entry.level] or vim.log.levels.INFO)
end

---Log to file
---@param entry LogEntry
function PlugmanLogger:_log_to_file(entry)
    if not self.log_file then
        return
    end

    local line = string.format('[%s] [%s] %s',
        entry.timestamp,
        entry.level:upper(),
        entry.message
    )

    if entry.source then
        line = line .. string.format(' [%s]', entry.source)
    end

    if entry.data then
        line = line .. string.format(' DATA: %s', vim.inspect(entry.data))
    end

    self.log_file:write(line .. '\n')
end

---Flush logs to file
function PlugmanLogger:flush()
    if self.log_file then
        self.log_file:flush()
    end
end

---Close logger
function PlugmanLogger:close()
    if self.flush_timer then
        self.flush_timer:stop()
        self.flush_timer = nil
    end

    if self.log_file then
        self.log_file:close()
        self.log_file = nil
    end
end

---Set log level
---@param level string
function PlugmanLogger:set_level(level)
    if self.levels[level] then
        self.current_level = self.levels[level]
        self.config.level = level
        self:info('Log level changed to: ' .. level)
    else
        self:warn('Invalid log level: ' .. level)
    end
end

---Get recent log entries
---@param count number?
---@return LogEntry[]
function PlugmanLogger:get_recent(count)
    count = count or 50
    local recent = {}

    -- Get entries from buffer
    local current_index = self.buffer_index
    for i = 1, math.min(count, self.config.buffer_size) do
        local index = current_index - i
        if index < 1 then
            index = index + self.config.buffer_size
        end

        local entry = self.buffer[index]
        if entry then
            table.insert(recent, 1, entry)
        else
            break
        end
    end

    return recent
end

---Get log statistics
---@return table
function PlugmanLogger:get_stats()
    local stats = {
        total_entries = 0,
        by_level = {},
        file_size = 0,
        buffer_usage = 0,
    }

    -- Count buffer entries
    for _, entry in pairs(self.buffer) do
        if entry then
            stats.total_entries = stats.total_entries + 1
            stats.by_level[entry.level] = (stats.by_level[entry.level] or 0) + 1
        end
    end

    stats.buffer_usage = stats.total_entries / self.config.buffer_size * 100

    -- Get file size
    if self.log_file_path then
        local stat = vim.loop.fs_stat(self.log_file_path)
        if stat then
            stats.file_size = stat.size
        end
    end

    return stats
end

---Clear log buffer
function PlugmanLogger:clear_buffer()
    self.buffer = {}
    self.buffer_index = 1
    self:info('Log buffer cleared')
end

---Export logs to file
---@param filepath string
---@return boolean
function PlugmanLogger:export(filepath)
    local recent = self:get_recent()
    local lines = {}

    for _, entry in ipairs(recent) do
        local line = string.format('[%s] [%s] %s',
            entry.timestamp,
            entry.level:upper(),
            entry.message
        )

        if entry.source then
            line = line .. string.format(' [%s]', entry.source)
        end

        table.insert(lines, line)
    end

    return utils.write_file(filepath, table.concat(lines, '\n'))
end

-- Convenience methods for different log levels
function PlugmanLogger:trace(message, source, data) self:log('trace', message, source, data) end

function PlugmanLogger:debug(message, source, data) self:log('debug', message, source, data) end

function PlugmanLogger:info(message, source, data) self:log('info', message, source, data) end

function PlugmanLogger:warn(message, source, data) self:log('warn', message, source, data) end

function PlugmanLogger:error(message, source, data) self:log('error', message, source, data) end

function PlugmanLogger:fatal(message, source, data) self:log('fatal', message, source, data) end

-- Module exports
local M = {}

---Initialize the logger with config
---@param config table
---@return PlugmanLogger
function M.setup(config)
    if not _instance then
        _instance = PlugmanLogger:new(config)
        _instance:_init()
    end
    return _instance
end

---Get the logger instance
---@return PlugmanLogger
function M.get()
    if not _instance then
        error('Logger not initialized. Call setup() first.')
    end
    return _instance
end

-- Convenience methods that delegate to the instance
function M.trace(message, source, data)
    return M.get():trace(message, source, data)
end

function M.debug(message, source, data)
    return M.get():debug(message, source, data)
end

function M.info(message, source, data)
    return M.get():info(message, source, data)
end

function M.warn(message, source, data)
    return M.get():warn(message, source, data)
end

function M.error(message, source, data)
    return M.get():error(message, source, data)
end

function M.fatal(message, source, data)
    return M.get():fatal(message, source, data)
end

return M
