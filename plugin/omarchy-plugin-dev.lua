if vim.g.loaded_omarchy_plugin_dev == 1 then
  return
end
vim.g.loaded_omarchy_plugin_dev = 1

require("omarchy_plugin_dev")._load()
