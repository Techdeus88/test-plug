-- Prevent loading twice
if vim.g.loaded_plugman then
  return
end
vim.g.loaded_plugman = 1

if not vim.g.plugman_no_auto_setup then
  -- Auto-setup if config exists
  local config_path = vim.fn.stdpath('config') .. '/lua/plugman_config.lua'
  if vim.loop.fs_stat(config_path) then
    local ok, config = pcall(dofile, config_path)
    if ok then
      require('plugman').setup(config)
    end
  end
end
