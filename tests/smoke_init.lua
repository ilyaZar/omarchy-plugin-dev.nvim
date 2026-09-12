local plugin_root = vim.fn.getcwd()
local overseer_root = vim.env.OMARCHY_PLUGIN_DEV_OVERSEER_ROOT
  or vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "overseer.nvim")

assert(
  vim.fn.isdirectory(overseer_root) == 1,
  "overseer.nvim is not installed at " .. overseer_root
)

vim.g.maplocalleader = "\\"
vim.opt.runtimepath:prepend(overseer_root)
vim.opt.runtimepath:prepend(plugin_root)

require("overseer").setup()
vim.cmd.runtime("plugin/omarchy-plugin-dev.lua")
require("omarchy_plugin_dev").setup()
