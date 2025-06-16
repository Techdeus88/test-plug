local M = {}

local start_time = nil
local benchmarks = {}

---Start benchmarking
function M.start()
    start_time = vim.loop.hrtime()
    benchmarks = {}
end

---Record a benchmark
---@param name string
---@param duration number
function M.record(name, duration)
    table.insert(benchmarks, {
        name = name,
        duration = duration,
        timestamp = vim.loop.hrtime()
    })
end

---Generate benchmark report
function M.report()
    if not start_time then
        vim.notify('No benchmark data available', vim.log.levels.WARN)
        return
    end

    local total_time = (vim.loop.hrtime() - start_time) / 1e6
    local plugman = require('plugman')

    local report_lines = {}
    table.insert(report_lines, '# Plugman Performance Report')
    table.insert(report_lines, '')
    table.insert(report_lines, string.format('Total startup time: %.2fms', total_time))
    table.insert(report_lines, '')

    -- Plugin load times
    table.insert(report_lines, '## Plugin Load Times')
    local plugins_list = {}
    for _, plugin in pairs(plugman.plugins) do
        if plugin.loaded then
            table.insert(plugins_list, plugin)
        end
    end

    table.sort(plugins_list, function(a, b)
        return a.load_time > b.load_time
    end)

    for _, plugin in ipairs(plugins_list) do
        table.insert(report_lines, string.format('- %s: %.2fms', plugin.name, plugin.load_time))
    end

    -- Benchmarks
    if #benchmarks > 0 then
        table.insert(report_lines, '')
        table.insert(report_lines, '## Benchmarks')
        for _, bench in ipairs(benchmarks) do
            table.insert(report_lines, string.format('- %s: %.2fms', bench.name, bench.duration))
        end
    end

    -- Create benchmark report buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, report_lines)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)

    vim.cmd('split')
    vim.api.nvim_win_set_buf(0, buf)
end

return M
