local PlugmanDashboard = {}
PlugmanDashboard.__index = PlugmanDashboard

local utils = require('plugman.core.utils')

---Create new dashboard instance
---@param config PlugmanConfig
---@return PlugmanDashboard
function PlugmanDashboard:new(config)
    ---@class PlugmanDashboard
    local dashboard = setmetatable({}, self)
    dashboard.config = config
    dashboard.buf = nil
    dashboard.win = nil
    dashboard.update_timer = nil
    dashboard.auto_refresh = true
    dashboard.refresh_interval = 1000
    dashboard.sections = {
        'header',
        'stats',
        'status',
        'plugins',
        'logs',
        'keymaps'
    }
    dashboard.current_section = 'plugins'
    dashboard.selected_plugin = 1
    dashboard.scroll_offset = 0
    dashboard.filter = ''
    dashboard.show_disabled = true
    dashboard.show_lazy = true
    dashboard.sort_by = 'name' -- name, status, load_time, priority
    dashboard.sort_desc = false

    -- Real-time update listeners
    dashboard.listeners = {}
    dashboard:_setup_event_listeners()

    return dashboard
end

---Setup event listeners for real-time updates
function PlugmanDashboard:_setup_event_listeners()
    -- Listen for plugin events
    vim.api.nvim_create_autocmd('User', {
        group = vim.api.nvim_create_augroup('PlugmanDashboard', { clear = true }),
        pattern = {
            'PlugmanPluginLoaded',
            'PlugmanPluginInstalled',
            'PlugmanPluginUpdated',
            'PlugmanPluginRemoved',
            'PlugmanPluginError'
        },
        callback = function(ev)
            self:_handle_plugin_event(ev)
        end,
    })
end

---Handle plugin events for real-time updates
---@param ev table
function PlugmanDashboard:_handle_plugin_event(ev)
    if not self:is_open() then
        return
    end

    -- Add to activity log
    local timestamp = os.date('%H:%M:%S')
    local message = string.format('[%s] %s: %s', timestamp, ev.pattern, ev.data.name or 'unknown')

    table.insert(self.activity_log, message)
    if #self.activity_log > 50 then
        table.remove(self.activity_log, 1)
    end

    -- Refresh dashboard
    if self.auto_refresh then
        self:refresh()
    end
end

---Check if dashboard is open
---@return boolean
function PlugmanDashboard:is_open()
    return self.win and vim.api.nvim_win_is_valid(self.win)
end

---Open the dashboard
function PlugmanDashboard:open()
    if self:is_open() then
        vim.api.nvim_set_current_win(self.win)
        return
    end

    self:_create_window()
    self:_setup_keymaps()
    self:_setup_autocmds()
    self:refresh()
    self:_start_auto_refresh()
end

---Create the dashboard window
function PlugmanDashboard:_create_window()
    self.buf = vim.api.nvim_create_buf(false, true)

    local width = math.floor(vim.o.columns * 0.9)
    local height = math.floor(vim.o.lines * 0.9)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    self.win = vim.api.nvim_open_win(self.buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' Plugman Dashboard ',
        title_pos = 'center',
    })

    -- Set buffer options
    vim.api.nvim_buf_set_option(self.buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(self.buf, 'filetype', 'plugman-dashboard')
    vim.api.nvim_buf_set_option(self.buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(self.buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(self.buf, 'swapfile', false)

    -- Window options
    vim.api.nvim_win_set_option(self.win, 'wrap', false)
    vim.api.nvim_win_set_option(self.win, 'cursorline', true)
    vim.api.nvim_win_set_option(self.win, 'number', false)
    vim.api.nvim_win_set_option(self.win, 'relativenumber', false)
    vim.api.nvim_win_set_option(self.win, 'signcolumn', 'no')

    -- Initialize activity log
    self.activity_log = {}
end

---Refresh dashboard content
function PlugmanDashboard:refresh()
    if not self:is_open() then
        return
    end

    local lines = {}
    local highlights = {}
    local line_num = 0

    -- Render each section
    for _, section in ipairs(self.sections) do
        local section_lines, section_highlights = self:_render_section(section, line_num)

        for _, line in ipairs(section_lines) do
            table.insert(lines, line)
            line_num = line_num + 1
        end

        for _, hl in ipairs(section_highlights) do
            table.insert(highlights, hl)
        end
    end

    -- Update buffer content
    vim.api.nvim_buf_set_option(self.buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(self.buf, 'modifiable', false)

    -- Apply highlights
    self:_apply_highlights(highlights)

    -- Update cursor position if needed
    self:_update_cursor()
end

---Render a specific section
---@param section string
---@param start_line number
---@return table, table
function PlugmanDashboard:_render_section(section, start_line)
    local lines = {}
    local highlights = {}

    if section == 'header' then
        lines, highlights = self:_render_header(start_line)
    elseif section == 'stats' then
        lines, highlights = self:_render_stats(start_line)
    elseif section == 'status' then
        lines, highlights = self:_render_status(start_line)
    elseif section == 'plugins' then
        lines, highlights = self:_render_plugins(start_line)
    elseif section == 'logs' then
        lines, highlights = self:_render_logs(start_line)
    elseif section == 'keymaps' then
        lines, highlights = self:_render_keymaps(start_line)
    end

    return lines, highlights
end

---Render header section
---@param start_line number
---@return table, table
function PlugmanDashboard:_render_header(start_line)
    local lines = {
        '',
        '╭─────────────────── Plugman Dashboard ────────────────────╮',
        '│           A modern plugin manager for Neovim             │',
        '╰──────────────────────────────────────────────────────────╯',
        ''
    }

    local highlights = {
        { line = start_line,     col_start = 0, col_end = -1, hl_group = 'Title' },
        { line = start_line + 1, col_start = 0, col_end = -1, hl_group = 'Comment' },
    }

    return lines, highlights
end

---Render stats section
---@param start_line number
---@return table, table
function PlugmanDashboard:_render_stats(start_line)
    local plugman = require('plugman')
    local stats = plugman.api:stats()

    local lines = {
        '📊 Statistics',
        string.rep('─', 60),
        string.format('  Total Plugins: %d', stats.total),
        string.format('  ✅ Loaded: %d', stats.loaded),
        string.format('  ⏳ Lazy: %d', stats.lazy),
        string.format('  ❌ Disabled: %d', stats.disabled),
        string.format('  🚫 Errors: %d', stats.errors),
        string.format('  ⚡ Load Time: %s', utils.format_time(stats.total_load_time)),
        ''
    }

    local highlights = {
        { line = start_line,     col_start = 0, col_end = -1, hl_group = 'Function' },
        { line = start_line + 1, col_start = 0, col_end = -1, hl_group = 'Comment' },
    }

    -- Color code stats
    local stat_colors = {
        { pattern = '✅', hl_group = 'DiagnosticOk' },
        { pattern = '⏳', hl_group = 'DiagnosticWarn' },
        { pattern = '❌', hl_group = 'Comment' },
        { pattern = '🚫', hl_group = 'DiagnosticError' },
        { pattern = '⚡', hl_group = 'String' },
    }

    for i = 2, #lines - 1 do
        for _, color in ipairs(stat_colors) do
            local col_start, col_end = lines[i]:find(color.pattern)
            if col_start then
                table.insert(highlights, {
                    line = start_line + i,
                    col_start = col_start - 1,
                    col_end = col_end,
                    hl_group = color.hl_group
                })
            end
        end
    end

    return lines, highlights
end

---Render status section
---@param start_line number
---@return table, table
function PlugmanDashboard:_render_status(start_line)
    local lines = {
        '🔄 Recent Activity',
        string.rep('─', 60),
    }

    local highlights = {
        { line = start_line,     col_start = 0, col_end = -1, hl_group = 'Function' },
        { line = start_line + 1, col_start = 0, col_end = -1, hl_group = 'Comment' },
    }

    -- Show recent activity
    local recent_count = math.min(5, #self.activity_log)
    for i = #self.activity_log - recent_count + 1, #self.activity_log do
        if self.activity_log[i] then
            table.insert(lines, '  ' .. self.activity_log[i])
        end
    end

    if recent_count == 0 then
        table.insert(lines, '  No recent activity')
        table.insert(highlights, {
            line = start_line + #lines - 1,
            col_start = 0,
            col_end = -1,
            hl_group = 'Comment'
        })
    end

    table.insert(lines, '')

    return lines, highlights
end

---Render plugins section
---@param start_line number
---@return table, table
function PlugmanDashboard:_render_plugins(start_line)
    local plugman = require('plugman')
    local lines = {
        string.format('🔌 Plugins (Sort: %s %s) [Filter: %s]',
            self.sort_by,
            self.sort_desc and '↓' or '↑',
            self.filter == '' and 'none' or self.filter),
        string.rep('─', 80),
        string.format('%-3s %-25s %-10s %-8s %-12s %s',
            '', 'Name', 'Status', 'Load', 'Priority', 'Source'),
        string.rep('─', 80),
    }

    local highlights = {
        { line = start_line,     col_start = 0, col_end = -1, hl_group = 'Function' },
        { line = start_line + 1, col_start = 0, col_end = -1, hl_group = 'Comment' },
        { line = start_line + 2, col_start = 0, col_end = -1, hl_group = 'Identifier' },
        { line = start_line + 3, col_start = 0, col_end = -1, hl_group = 'Comment' },
    }

    -- Get filtered and sorted plugins
    local plugins_list = self:_get_filtered_plugins(plugman.plugins)
    self:_sort_plugins(plugins_list)

    -- Store plugin lines for navigation
    self.plugin_lines = {}

    for i, plugin in ipairs(plugins_list) do
        local status_icon = self:_get_status_icon(plugin)
        local status_text = self:_get_status_text(plugin)
        local load_time = plugin.loaded and utils.format_time(plugin.load_time) or '-'
        local priority = tostring(plugin.priority)
        local source = plugin.source:sub(1, 30) .. (plugin.source:len() > 30 and '...' or '')

        local cursor_indicator = (i == self.selected_plugin) and '►' or ' '

        local line = string.format('%s %s %-25s %-10s %-8s %-12s %s',
            cursor_indicator,
            status_icon,
            plugin.name:sub(1, 24),
            status_text,
            load_time,
            priority,
            source
        )

        table.insert(lines, line)
        table.insert(self.plugin_lines, {
            plugin = plugin,
            line_num = start_line + #lines - 1
        })

        -- Add highlights for status
        local hl_group = self:_get_status_highlight(plugin)
        table.insert(highlights, {
            line = start_line + #lines - 1,
            col_start = 2,
            col_end = 3,
            hl_group = hl_group
        })

        -- Highlight selected line
        if i == self.selected_plugin then
            table.insert(highlights, {
                line = start_line + #lines - 1,
                col_start = 0,
                col_end = 1,
                hl_group = 'Visual'
            })
        end
    end

    table.insert(lines, '')

    return lines, highlights
end

---Render logs section
---@param start_line number
---@return table, table
function PlugmanDashboard:_render_logs(start_line)
    local logger = require('plugman.logger')
    local recent_logs = logger.get():get_recent(10)

    local lines = {
        '📋 Recent Logs',
        string.rep('─', 60),
    }

    local highlights = {
        { line = start_line,     col_start = 0, col_end = -1, hl_group = 'Function' },
        { line = start_line + 1, col_start = 0, col_end = -1, hl_group = 'Comment' },
    }

    for _, log_entry in ipairs(recent_logs) do
        local prefix = string.format('[%s] %s:', log_entry.timestamp, log_entry.level:upper())
        local line = string.format('  %s %s', prefix, log_entry.message)
        table.insert(lines, line)

        -- Color code by log level
        local hl_group = 'Normal'
        if log_entry.level == 'error' then
            hl_group = 'DiagnosticError'
        elseif log_entry.level == 'warn' then
            hl_group = 'DiagnosticWarn'
        elseif log_entry.level == 'info' then
            hl_group = 'DiagnosticInfo'
        elseif log_entry.level == 'debug' then
            hl_group = 'Comment'
        end

        table.insert(highlights, {
            line = start_line + #lines - 1,
            col_start = 2,
            col_end = 2 + #prefix,
            hl_group = hl_group
        })
    end

    table.insert(lines, '')

    return lines, highlights
end

---Render keymaps section
---@param start_line number
---@return table, table
function PlugmanDashboard:_render_keymaps(start_line)
    local keymaps = {
        { key = 'q',       desc = 'Close dashboard' },
        { key = '<Esc>',   desc = 'Close dashboard' },
        { key = 'r',       desc = 'Refresh' },
        { key = 'j/k',     desc = 'Navigate plugins' },
        { key = '<Enter>', desc = 'Plugin details' },
        { key = 's',       desc = 'Sync plugins' },
        { key = 'c',       desc = 'Clean plugins' },
        { key = 'i',       desc = 'Install plugin' },
        { key = 'd',       desc = 'Remove plugin' },
        { key = 't',       desc = 'Toggle plugin' },
        { key = '/',       desc = 'Filter plugins' },
        { key = 'o',       desc = 'Sort options' },
        { key = 'l',       desc = 'View logs' },
        { key = 'h',       desc = 'Health check' },
    }

    local lines = {
        '⌨️  Keymaps',
        string.rep('─', 40),
    }

    local highlights = {
        { line = start_line,     col_start = 0, col_end = -1, hl_group = 'Function' },
        { line = start_line + 1, col_start = 0, col_end = -1, hl_group = 'Comment' },
    }

    for _, keymap in ipairs(keymaps) do
        local line = string.format('  %-10s %s', keymap.key, keymap.desc)
        table.insert(lines, line)

        -- Highlight key
        table.insert(highlights, {
            line = start_line + #lines - 1,
            col_start = 2,
            col_end = 2 + #keymap.key,
            hl_group = 'Special'
        })
    end

    return lines, highlights
end

---Apply highlights to buffer
---@param highlights table
function PlugmanDashboard:_apply_highlights(highlights)
    -- Clear existing highlights
    vim.api.nvim_buf_clear_namespace(self.buf, -1, 0, -1)

    -- Apply new highlights
    for _, hl in ipairs(highlights) do
        if hl.col_end == -1 then
            hl.col_end = 0
        end
        vim.api.nvim_buf_add_highlight(self.buf, -1, hl.hl_group, hl.line, hl.col_start, hl.col_end)
    end
end

---Get filtered plugins based on current filter settings
---@param plugins table
---@return table
function PlugmanDashboard:_get_filtered_plugins(plugins)
    local filtered = {}

    for _, plugin in pairs(plugins) do
        local include = true

        -- Filter by disabled status
        if not self.show_disabled and not plugin.enabled then
            include = false
        end

        -- Filter by lazy status
        if not self.show_lazy and plugin.lazy then
            include = false
        end

        -- Filter by search term
        if self.filter ~= '' then
            local search_text = (plugin.name .. ' ' .. plugin.source):lower()
            if not search_text:find(self.filter:lower(), 1, true) then
                include = false
            end
        end

        if include then
            table.insert(filtered, plugin)
        end
    end

    return filtered
end

---Sort plugins based on current sort settings
---@param plugins table
function PlugmanDashboard:_sort_plugins(plugins)
    -- Define status priority for consistent sorting
    local status_priority = {
        loaded = 1,
        not_loaded = 2,
        disabled = 3,
        error = 4
    }

    table.sort(plugins, function(a, b)
        local result

        if self.sort_by == 'name' then
            result = a.name < b.name
        elseif self.sort_by == 'status' then
            local status_a = status_priority[a:status()] or 5
            local status_b = status_priority[b:status()] or 5
            result = status_a < status_b
        elseif self.sort_by == 'load_time' then
            result = (a.load_time or 0) < (b.load_time or 0)
        elseif self.sort_by == 'priority' then
            result = (a.priority or 50) < (b.priority or 50)
        else
            result = a.name < b.name
        end

        return self.sort_desc and not result or result
    end)
end

---Get status icon for plugin
---@param plugin PlugmanPlugin
---@return string
function PlugmanDashboard:_get_status_icon(plugin)
    local status = plugin:status()

    if status == 'loaded' then
        return '●'
    elseif status == 'error' then
        return '✗'
    elseif status == 'disabled' then
        return '○'
    else
        return '⋯'
    end
end

---Get status text for plugin
---@param plugin PlugmanPlugin
---@return string
function PlugmanDashboard:_get_status_text(plugin)
    local status = plugin:status()

    if status == 'loaded' then
        return plugin.lazy and 'lazy' or 'loaded'
    elseif status == 'error' then
        return 'error'
    elseif status == 'disabled' then
        return 'disabled'
    else
        return 'pending'
    end
end

---Get status highlight group for plugin
---@param plugin PlugmanPlugin
---@return string
function PlugmanDashboard:_get_status_highlight(plugin)
    local status = plugin:status()

    if status == 'loaded' then
        return 'DiagnosticOk'
    elseif status == 'error' then
        return 'DiagnosticError'
    elseif status == 'disabled' then
        return 'Comment'
    else
        return 'DiagnosticWarn'
    end
end

---Setup dashboard keymaps
function PlugmanDashboard:_setup_keymaps()
    local opts = { buffer = self.buf, nowait = true, silent = true }

    -- Navigation
    vim.keymap.set('n', 'q', function() self:close() end, opts)
    vim.keymap.set('n', '<Esc>', function() self:close() end, opts)
    vim.keymap.set('n', 'r', function() self:refresh() end, opts)
    vim.keymap.set('n', 'j', function() self:_navigate_plugin(1) end, opts)
    vim.keymap.set('n', 'k', function() self:_navigate_plugin(-1) end, opts)
    vim.keymap.set('n', '<Down>', function() self:_navigate_plugin(1) end, opts)
    vim.keymap.set('n', '<Up>', function() self:_navigate_plugin(-1) end, opts)

    -- Plugin actions
    vim.keymap.set('n', '<Enter>', function() self:_show_plugin_details() end, opts)
    vim.keymap.set('n', 's', function() self:_sync_plugins() end, opts)
    vim.keymap.set('n', 'c', function() self:_clean_plugins() end, opts)
    vim.keymap.set('n', 'i', function() self:_install_plugin() end, opts)
    vim.keymap.set('n', 'd', function() self:_remove_plugin() end, opts)
    vim.keymap.set('n', 't', function() self:_toggle_plugin() end, opts)

    -- Filtering and sorting
    vim.keymap.set('n', '/', function() self:_filter_plugins() end, opts)
    vim.keymap.set('n', 'o', function() self:_sort_options() end, opts)

    -- Other actions
    vim.keymap.set('n', 'l', function() self:_view_logs() end, opts)
    vim.keymap.set('n', 'h', function() self:_health_check() end, opts)
    vim.keymap.set('n', 'R', function() self:_reload_config() end, opts)
end

---Setup dashboard autocmds
function PlugmanDashboard:_setup_autocmds()
    local group = vim.api.nvim_create_augroup('PlugmanDashboardBuffer', { clear = true })

    -- Close dashboard when buffer is deleted
    vim.api.nvim_create_autocmd('BufDelete', {
        group = group,
        buffer = self.buf,
        callback = function()
            self:close()
        end,
    })

    -- Handle window resize
    vim.api.nvim_create_autocmd('VimResized', {
        group = group,
        callback = function()
            if self:is_open() then
                self:refresh()
            end
        end,
    })
end

---Start auto-refresh timer
function PlugmanDashboard:_start_auto_refresh()
    if self.update_timer then
        self.update_timer:stop()
    end

    if self.auto_refresh then
        self.update_timer = vim.loop.new_timer()
        self.update_timer:start(self.refresh_interval, self.refresh_interval, vim.schedule_wrap(function()
            if self:is_open() then
                self:refresh()
            else
                self:_stop_auto_refresh()
            end
        end))
    end
end

---Stop auto-refresh timer
function PlugmanDashboard:_stop_auto_refresh()
    if self.update_timer then
        self.update_timer:stop()
        self.update_timer = nil
    end
end

---Navigate plugin selection
---@param direction number
function PlugmanDashboard:_navigate_plugin(direction)
    if not self.plugin_lines or #self.plugin_lines == 0 then
        return
    end

    -- Validate window and buffer
    if not self.win or not vim.api.nvim_win_is_valid(self.win) then
        return
    end

    self.selected_plugin = math.max(1, math.min(#self.plugin_lines, self.selected_plugin + direction))

    -- Update cursor position
    local line_info = self.plugin_lines[self.selected_plugin]
    if line_info then
        local buf = vim.api.nvim_win_get_buf(self.win)
        local line_count = vim.api.nvim_buf_line_count(buf)
        if line_info.line_num + 1 <= line_count then
            vim.api.nvim_win_set_cursor(self.win, { line_info.line_num + 1, 0 })
        end
    end

    self:refresh()
end

---Update cursor position
function PlugmanDashboard:_update_cursor()
    if not self.plugin_lines or #self.plugin_lines == 0 then
        return
    end

    -- Validate window and buffer
    if not self.win or not vim.api.nvim_win_is_valid(self.win) then
        return
    end

    local line_info = self.plugin_lines[self.selected_plugin]
    if line_info then
        local buf = vim.api.nvim_win_get_buf(self.win)
        local line_count = vim.api.nvim_buf_line_count(buf)
        if line_info.line_num + 1 <= line_count then
            vim.api.nvim_win_set_cursor(self.win, { line_info.line_num + 1, 0 })
        end
    end
end

---Show plugin details
function PlugmanDashboard:_show_plugin_details()
    if not self.plugin_lines or #self.plugin_lines == 0 then
        return
    end

    local line_info = self.plugin_lines[self.selected_plugin]
    if not line_info then
        return
    end

    local plugin = line_info.plugin
    if not plugin then
        return
    end

    -- Create plugin details popup
    local details = {
        'Plugin Details',
        string.rep('═', 50),
        '',
        'Name: ' .. (plugin.name or 'unknown'),
        'Source: ' .. (plugin.source or 'unknown'),
        'Enabled: ' .. (plugin.enabled and 'yes' or 'no'),
        '',
        'Status: ' .. (plugin:status() or 'unknown'),
        'Lazy: ' .. (plugin.lazy and 'yes' or 'no'),
        'Priority: ' .. (plugin.priority or 'unknown'),
        'In-Session' .. (plugin.added and 'yes' or 'no'),
        'Installed: ' .. (plugin:is_installed() and 'yes' or 'no'),
        'Load Time: ' .. (plugin.loaded and utils.format_time(plugin.load_time) or 'not loaded'),
        '',
        'Dependencies: ' .. (plugin.depends and next(plugin.depends) and table.concat(plugin.depends, ', ') or 'none'),
        'Events: ' .. (plugin.event and next(plugin.event) and table.concat(plugin.event, ', ') or 'none'),
        'Commands: ' .. (plugin.cmd and next(plugin.cmd) and #plugin.cmd or 'none'),
        'Filetypes: ' .. (plugin.ft and next(plugin.ft) and table.concat(plugin.ft, ', ') or 'none'),
        'Keys: ' .. (plugin.keys and next(plugin.keys) and #plugin.keys .. 'keymap' or 'none' .. #plugin.keys > 1 and 's' or ''),
        '',
        'Configuration:',
        vim.inspect(plugin.config or {}, { indent = '  ' }),
        vim.inspect(plugin.opts or {}, { indent = '  ' }),
    }

    -- Show in floating window
    local popup_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, details)
    vim.api.nvim_buf_set_option(popup_buf, 'filetype', 'yaml')
    vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)

    local popup_win = vim.api.nvim_open_win(popup_buf, true, {
        relative = 'editor',
        width = math.min(80, vim.o.columns - 10),
        height = math.min(#details + 2, vim.o.lines - 10),
        row = math.floor((vim.o.lines - #details) / 2),
        col = math.floor((vim.o.columns - 80) / 2),
        style = 'minimal',
        border = 'rounded',
        title = ' ' .. plugin.name .. ' ',
        title_pos = 'center',
    })

    vim.keymap.set('n', 'q', function()
        vim.api.nvim_win_close(popup_win, true)
    end, { buffer = popup_buf })
end

---View logs in a dedicated window
function PlugmanDashboard:_view_logs()
    local logger = require('plugman.logger')
    local recent_logs = logger.get():get_recent(100) -- Get more logs for the dedicated view

    -- Create log entries with proper formatting
    local log_lines = {
        '📋 Plugman Logs',
        string.rep('═', 80),
        '',
    }

    -- Add log entries
    for _, log_entry in ipairs(recent_logs) do
        local prefix = string.format('[%s] %s:', log_entry.timestamp, log_entry.level:upper())
        local line = string.format('%s %s', prefix, log_entry.message)
        if log_entry.source then
            line = line .. string.format(' [%s]', log_entry.source)
        end
        table.insert(log_lines, line)
    end

    -- Create and configure buffer
    local log_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, log_lines)
    vim.api.nvim_buf_set_option(log_buf, 'filetype', 'log')
    vim.api.nvim_buf_set_option(log_buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(log_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(log_buf, 'swapfile', false)

    -- Calculate window dimensions
    local width = math.min(100, vim.o.columns - 10)
    local height = math.min(#log_lines + 2, vim.o.lines - 10)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    -- Create and configure window
    local log_win = vim.api.nvim_open_win(log_buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' Plugman Logs ',
        title_pos = 'center',
    })

    -- Set window options
    vim.api.nvim_win_set_option(log_win, 'wrap', false)
    vim.api.nvim_win_set_option(log_win, 'cursorline', true)
    vim.api.nvim_win_set_option(log_win, 'number', true)
    vim.api.nvim_win_set_option(log_win, 'relativenumber', false)

    -- Add keymaps
    local opts = { buffer = log_buf, nowait = true, silent = true }
    vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(log_win, true) end, opts)
    vim.keymap.set('n', '<Esc>', function() vim.api.nvim_win_close(log_win, true) end, opts)
    vim.keymap.set('n', 'r', function()
        -- Refresh logs
        local new_logs = logger.get():get_recent(100)
        local new_lines = {
            '📋 Plugman Logs',
            string.rep('═', 80),
            '',
        }
        for _, log_entry in ipairs(new_logs) do
            local prefix = string.format('[%s] %s:', log_entry.timestamp, log_entry.level:upper())
            local line = string.format('%s %s', prefix, log_entry.message)
            if log_entry.source then
                line = line .. string.format(' [%s]', log_entry.source)
            end
            table.insert(new_lines, line)
        end
        vim.api.nvim_buf_set_option(log_buf, 'modifiable', true)
        vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, new_lines)
        vim.api.nvim_buf_set_option(log_buf, 'modifiable', false)
    end, opts)

    -- Add syntax highlighting
    local ns = vim.api.nvim_create_namespace('plugman_logs')
    for i, line in ipairs(log_lines) do
        if i > 3 then -- Skip header lines
            local level = line:match('%[(%w+)%]')
            if level then
                local hl_group = 'Normal'
                if level == 'ERROR' then
                    hl_group = 'DiagnosticError'
                elseif level == 'WARN' then
                    hl_group = 'DiagnosticWarn'
                elseif level == 'INFO' then
                    hl_group = 'DiagnosticInfo'
                elseif level == 'DEBUG' then
                    hl_group = 'Comment'
                end
                vim.api.nvim_buf_add_highlight(log_buf, ns, hl_group, i - 1, 0, -1)
            end
        end
    end
end

---Close dashboard
function PlugmanDashboard:close()
    self:_stop_auto_refresh()

    if self.win and vim.api.nvim_win_is_valid(self.win) then
        vim.api.nvim_win_close(self.win, true)
    end

    self.win = nil
    self.buf = nil
end

-- Additional action methods would be implemented here
-- (sync, clean, install, remove, toggle, filter, etc.)

return PlugmanDashboard
