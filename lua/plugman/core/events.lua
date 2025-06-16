local Logger = require('plugman.logger')

---@class PlugmanEvents
local Events = {}
Events.__index = Events

-- Event groups for better organization
local EVENT_GROUPS = {
    buffer = {
        'BufAdd', 'BufDelete', 'BufEnter', 'BufLeave', 'BufNew',
        'BufNewFile', 'BufRead', 'BufReadPost', 'BufReadPre',
        'BufUnload', 'BufWinEnter', 'BufWinLeave', 'BufWrite',
        'BufWritePre', 'BufWritePost',
    },
    file = {
        'FileType', 'FileReadCmd', 'FileWriteCmd', 'FileAppendCmd',
        'FileAppendPost', 'FileAppendPre', 'FileChangedShell',
        'FileChangedShellPost', 'FileReadPost', 'FileReadPre',
        'FileWritePost', 'FileWritePre',
    },
    window = {
        'WinClosed', 'WinEnter', 'WinLeave', 'WinNew', 'WinScrolled',
    },
    terminal = {
        'TermOpen', 'TermClose', 'TermEnter', 'TermLeave', 'TermChanged',
    },
    tab = {
        'TabEnter', 'TabLeave', 'TabNew', 'TabNewEntered',
    },
    text = {
        'TextChanged', 'TextChangedI', 'TextChangedP', 'TextYankPost',
    },
    insert = {
        'InsertChange', 'InsertCharPre', 'InsertEnter', 'InsertLeave',
    },
    vim = {
        'VimEnter', 'VimLeave', 'VimLeavePre', 'VimResized',
    },
    custom = {
        'DashboardUpdate', 'PluginLoad', 'PluginUnload', "Plugman", "PlugmanSuperLazy", "PlugmanReady"
    }
}

-- Create a set of all known events for quick lookup
local KNOWN_EVENTS = {}
for _, events in pairs(EVENT_GROUPS) do
    for _, event in ipairs(events) do
        KNOWN_EVENTS[event] = true
    end
end

-- Debounce configuration
local DEBOUNCE_CONFIG = {
    ['TextChanged'] = 100,
    ['TextChangedI'] = 100,
    ['TextChangedP'] = 100,
    ['WinScrolled'] = 50,
    ['CursorMoved'] = 50,
    ['CursorMovedI'] = 50,
}

---Create new events system
---@param loader PlugmanLoader
---@return PlugmanEvents
function Events.new(loader)
    ---@class PlugmanEvents
    local self = setmetatable({}, Events)

    self.loader = loader
    self.event_handlers = {}
    self.command_handlers = {}
    self.filetype_handlers = {}
    self.key_handlers = {}
    self.event_history = {}
    self.debug_mode = false
    self.ungrouped_handlers = {}
    self.debounce_timers = {}

    self:setup_autocmds()

    return self
end

---Setup autocmds for event handling
function Events:setup_autocmds()
    local group = vim.api.nvim_create_augroup('PlugmanEvents', { clear = true })

    -- Register events by group
    for group_name, events in pairs(EVENT_GROUPS) do
        local group = vim.api.nvim_create_augroup('Plugman' .. group_name, { clear = true })
        if group_name == "custom" then
            for _, event in ipairs(events) do
                vim.api.nvim_create_autocmd("User", {
                    pattern = event,
                    group = group,
                    callback = function(args)
                        self:handle_event(event, args)
                    end,
                })
            end
        else
            for _, event in ipairs(events) do
                vim.api.nvim_create_autocmd(event, {
                    group = group,
                    callback = function(args)
                        self:handle_event(event, args)
                    end,
                })
            end
        end
    end

    -- Handle ungrouped events
    vim.api.nvim_create_autocmd("User", {
        group = group,
        callback = function(args)
            local event = args.event
            if not KNOWN_EVENTS[event] then
                self:handle_event(event, args)
            end
        end,
    })
end

---Handle event with debouncing
---@param event string Event name
---@param args table Event arguments
function Events:handle_event(event, args)
    -- Check if event should be debounced
    local debounce_time = DEBOUNCE_CONFIG[event]
    if debounce_time then
        -- Cancel existing timer if any
        if self.debounce_timers[event] then
            self.debounce_timers[event]:stop()
        end

        -- Create new timer
        self.debounce_timers[event] = vim.defer_fn(function()
            self:_execute_handlers(event, args)
            self.debounce_timers[event] = nil
        end, debounce_time)
    else
        self:_execute_handlers(event, args)
    end
end

---Execute handlers for an event
---@param event string Event name
---@param args table Event arguments
function Events:_execute_handlers(event, args)
    local handlers = self.event_handlers[event]
    if not handlers then return end

    -- Execute handlers in order
    for _, handler in ipairs(handlers) do
        local ok, err = pcall(handler.callback, args)
        if not ok then
            Logger.error(string.format("Error in event handler for %s: %s", event, err))
        end
    end

    -- Record event in history
    table.insert(self.event_history, {
        event = event,
        time = vim.loop.now(),
        args = args
    })

    -- Trim history if too long
    if #self.event_history > 1000 then
        table.remove(self.event_history, 1)
    end
end

---Register event handler
---@param events string|table Event name(s)
---@param callback function Callback function
---@param opts table|nil Options
function Events:on_event(events, callback, opts)
    opts = opts or {}
    events = type(events) == 'table' and events or { events }

    for _, event in ipairs(events) do
        if not self.event_handlers[event] then
            self.event_handlers[event] = {}
        end

        -- Add handler with priority
        local handler = {
            callback = callback,
            priority = opts.priority or 0
        }

        table.insert(self.event_handlers[event], handler)
        -- Sort by priority (higher first)
        table.sort(self.event_handlers[event], function(a, b)
            return a.priority > b.priority
        end)
    end
end

---Unregister event handler
---@param events string|table Event name(s)
---@param callback function Callback function
function Events:off_event(events, callback)
    events = type(events) == 'table' and events or { events }

    for _, event in ipairs(events) do
        if self.event_handlers[event] then
            for i, handler in ipairs(self.event_handlers[event]) do
                if handler.callback == callback then
                    table.remove(self.event_handlers[event], i)
                    break
                end
            end
        end
    end
end

---Register command handler
---@param commands string|table Command name(s)
---@param callback function Callback function
---@param opts table|nil Options
function Events:on_command(commands, callback, opts)
    opts = opts or {}
    local cmd_list = type(commands) == 'table' and commands or { commands }

    for _, cmd in ipairs(cmd_list) do
        self.command_handlers[cmd] = {
            callback = callback,
            priority = opts.priority or 0,
            group = opts.group,
            debug = opts.debug
        }
    end
end

---Register filetype handler
---@param filetypes string|table Filetype(s)
---@param callback function Callback function
---@param opts table|nil Options
function Events:on_filetype(filetypes, callback, opts)
    opts = opts or {}
    local ft_list = type(filetypes) == 'table' and filetypes or { filetypes }

    for _, ft in ipairs(ft_list) do
        if not self.filetype_handlers[ft] then
            self.filetype_handlers[ft] = {}
        end
        table.insert(self.filetype_handlers[ft], {
            callback = callback,
            priority = opts.priority or 0,
            group = opts.group,
            debug = opts.debug
        })
        -- Sort handlers by priority (higher first)
        table.sort(self.filetype_handlers[ft], function(a, b)
            return a.priority > b.priority
        end)
    end
end

---Register key handler
---@param keys table Key specifications
---@param callback function Callback function
---@param opts table|nil Options
function Events:on_keys(keys, callback, opts)
    opts = opts or {}
    -- Ensure keys is a table
    if type(keys) ~= 'table' then
        Logger.error("on_keys: keys parameter must be a table, got " .. type(keys))
        return
    end
    for _, key in ipairs(keys) do
        local mode = key.mode or 'n'
        if type(mode) == "table" then
            -- Handle each mode separately
            for _, m in ipairs(mode) do
                local lhs = key.lhs or key[1]
                if lhs then
                    local key_id = m .. ':' .. lhs
                    self.key_handlers[key_id] = {
                        callback = callback,
                        priority = opts.priority or 0,
                        group = opts.group,
                        debug = opts.debug
                    }

                    -- Create lazy keymap for this mode
                    vim.keymap.set(m, lhs, function()
                        -- Execute callback first
                        callback()

                        -- Then execute the original mapping
                        vim.schedule(function()
                            local rhs = key.rhs or key[2]
                            if rhs then
                                if type(rhs) == 'function' then
                                    rhs()
                                else
                                    vim.cmd(rhs)
                                end
                            end
                        end)
                    end, { desc = key.desc })
                end
            end
        else
            local lhs = key.lhs or key[1]
            if lhs then
                local key_id = mode .. ':' .. lhs
                self.key_handlers[key_id] = {
                    callback = callback,
                    priority = opts.priority or 0,
                    group = opts.group,
                    debug = opts.debug
                }

                -- Create lazy keymap
                vim.keymap.set(mode, lhs, function()
                    -- Execute callback first
                    callback()

                    -- Then execute the original mapping
                    vim.schedule(function()
                        local rhs = key.rhs or key[2]
                        if rhs then
                            if type(rhs) == 'function' then
                                rhs()
                            else
                                vim.cmd(rhs)
                            end
                        end
                    end)
                end, { desc = key.desc })
            end
        end
    end
end

---Handle filetype
---@param filetype string Filetype
function Events:handle_filetype(filetype)
    local handlers = self.filetype_handlers[filetype]
    if handlers then
        for _, handler in ipairs(handlers) do
            -- Skip if handler is in debug mode and debug mode is off
            if handler.debug and not self.debug_mode then
                goto continue
            end

            local ok, err = pcall(handler.callback, filetype)
            if not ok then
                Logger.error("Filetype handler failed for " .. filetype .. ": " .. tostring(err))
            end

            ::continue::
        end
    end
end

---Enable/disable debug mode
---@param enabled boolean Whether debug mode should be enabled
function Events:set_debug_mode(enabled)
    self.debug_mode = enabled
end

---Get event history
---@return table Event history
function Events:get_event_history()
    return self.event_history
end

---Clear event history
function Events:clear_event_history()
    self.event_history = {}
end

vim.keymap.set("n", "<leader>EE", function() return Events:get_event_history() end, { desc = "Events History" })

return Events
