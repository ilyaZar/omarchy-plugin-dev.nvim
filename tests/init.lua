vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd.runtime("plugin/omarchy-plugin-dev.lua")
assert(package.loaded.omarchy_plugin_dev == nil, "plugin entrypoint eagerly loaded the main module")
assert(
  package.loaded["omarchy_plugin_dev.actions"] == nil,
  "plugin entrypoint eagerly loaded actions"
)
