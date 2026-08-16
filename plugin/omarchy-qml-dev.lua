if vim.g.loaded_omarchy_qml_dev == 1 then
  return
end
vim.g.loaded_omarchy_qml_dev = 1

require("omarchy_qml_dev")._load()
