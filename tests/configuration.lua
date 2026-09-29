local config = require("omarchy-plugin-dev.config")
local actions = require("omarchy-plugin-dev.actions")
local messages = require("omarchy-plugin-dev.messages")
local saved_config = vim.deepcopy(config.get())
local saved_show = messages.show
local saved_rtp = vim.o.runtimepath
local source_buf = vim.api.nvim_get_current_buf()
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/doc", "p")

for _, value in ipairs({ false, 12, {}, "" }) do
  local ok, err = pcall(config.setup, { config_file = value })
  assert(not ok and tostring(err):find("config_file", 1, true), "invalid config_file was accepted")
end

config.setup({ config_file = "lua/custom settings.lua" })
assert(
  config.user_config_path() == vim.fs.joinpath(vim.fn.stdpath("config"), "lua/custom settings.lua"),
  "relative config path does not use the active config directory"
)

local path = root .. "/settings | draft.lua"
vim.fn.writefile({ "vim.g.omadev_config_executed = true" }, path)
config.setup({ config_file = path })
assert(config.user_config_path() == path, "absolute config path was changed")
actions.edit_config()
assert(vim.api.nvim_buf_get_name(0) == path, "settings action opened the wrong file")
assert(vim.g.omadev_config_executed == nil, "settings action executed the file")
local settings_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_set_current_buf(source_buf)
vim.api.nvim_buf_delete(settings_buf, {})

local warning
messages.show = function(message)
  warning = message
end
config.setup({ config_file = root .. "/missing.lua" })
actions.edit_config()
assert(
  warning and warning:find("Config file not found:", 1, true),
  "missing config produced no warning"
)
assert(vim.api.nvim_get_current_buf() == source_buf, "missing config opened an empty buffer")
assert(vim.fn.filereadable(root .. "/missing.lua") == 0, "missing config was created")

vim.fn.writefile(
  vim.fn.readfile("doc/omarchy-plugin-dev.txt"),
  root .. "/doc/omarchy-plugin-dev.txt"
)
vim.cmd.helptags(vim.fn.fnameescape(root .. "/doc"))
vim.opt.runtimepath:append(root)
config.setup({})
assert(config.user_config_path() == nil, "config path was guessed")
actions.edit_config()
assert(vim.bo.filetype == "help", "settings fallback did not open help")
assert(vim.api.nvim_get_current_line():find("CONFIGURATION", 1, true), "wrong help section opened")
local help_buf = vim.api.nvim_get_current_buf()
vim.cmd.close()
vim.api.nvim_buf_delete(help_buf, {})

messages.show = saved_show
vim.o.runtimepath = saved_rtp
config.setup(saved_config)
assert(vim.fn.delete(root, "rf") == 0, "configuration fixture was not removed")
