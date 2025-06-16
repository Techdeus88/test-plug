---@class PlugmanUI
---@field dashboard PlugmanDashboard
---@field config PlugmanConfig
local PlugmanUI = {}
PlugmanUI.__index = PlugmanUI

local Dashboard = require('plugman.ui.dashboard')

---Create new UI instance
---@param config PlugmanConfig
---@return PlugmanUI
function PlugmanUI:new(config)
  local ui = setmetatable({}, self)
  ui.config = config
  ui.dashboard = Dashboard:new(config)
  return ui
end

---Open the main UI (dashboard)
function PlugmanUI:open()
  self.dashboard:open()
end

---Close the UI
function PlugmanUI:close()
  self.dashboard:close()
end

---Check if UI is open
---@return boolean
function PlugmanUI:is_open()
  return self.dashboard:is_open()
end

---Refresh the UI
function PlugmanUI:refresh()
  if self:is_open() then
    self.dashboard:refresh()
  end
end

return PlugmanUI