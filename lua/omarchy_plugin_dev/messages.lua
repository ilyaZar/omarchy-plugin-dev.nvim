local M = {}

function M.show(message, level)
  local config = require("omarchy_plugin_dev.config").get()
  if config.notify == false then
    return
  end
  vim.notify(message, level or config.log_level, { title = "Omarchy Plugin Dev" })
end

return M
