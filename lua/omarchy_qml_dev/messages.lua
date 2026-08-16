local M = {}

function M.show(message, level)
  local config = require("omarchy_qml_dev.config").get()
  if config.notify == false then
    return
  end
  vim.notify(message, level or config.log_level, { title = "Omarchy QML Dev" })
end

return M
