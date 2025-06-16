---@class PlugmanConfig
---@field plugins_dir string
---@field auto_install boolean
---@field auto_update boolean
---@field lazy_timeout number
---@field profile string
---@field cache_enabled boolean
---@field log_level string
local default_config = {
    plugins_dir = 'plugins',
    auto_install = true,
    auto_update = false,
    lazy_timeout = 2000,
    profile = 'default',
    cache_enabled = true,
    log_level = 'info',
    performance = {
        startup_timeout = 50,
        benchmark_enabled = false,
    },
    ui = {
        icons = {
            loaded = '●',
            not_loaded = '○',
            error = '✗',
            pending = '⋯',
        },
    },
}
return default_config
