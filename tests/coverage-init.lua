-- Compiled traces skip Lua line hooks.
jit.off()
local coverage = require("luacov.runner")
coverage.init({
  statsfile = "coverage/luacov.stats.out",
  reportfile = "coverage/luacov.report.out",
  runreport = true,
  includeuntestedfiles = { "lua", "plugin", "ftdetect" },
  modules = {
    ["omarchy-plugin-dev.*"] = "lua",
    ["plugin.omarchy-plugin-dev"] = "plugin/omarchy-plugin-dev.lua",
    ["ftdetect.omarchy-plugin-dev"] = "ftdetect/omarchy-plugin-dev.lua",
  },
})
vim.api.nvim_create_autocmd("VimLeavePre", {
  once = true,
  callback = function()
    coverage.shutdown()
  end,
})
dofile("tests/init.lua")
