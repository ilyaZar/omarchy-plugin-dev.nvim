if vim.g.loaded_omarchy_plugin_dev == 1 then
  return
end
vim.g.loaded_omarchy_plugin_dev = 1

require("omarchy-plugin-dev.filetype").setup()

local function command(name, callback, opts)
  opts = vim.tbl_extend("force", {
    desc = "Omarchy Plugin development action",
    force = false,
    nargs = 0,
  }, opts or {})
  vim.api.nvim_create_user_command(name, callback, opts)
end

command("OmaDev", function()
  require("omarchy-plugin-dev.actions").dashboard(0)
end, {
  desc = "Open the Omarchy Plugin project dashboard",
})
command("OmaDevInit", function(opts)
  require("omarchy-plugin-dev.actions").init_project(0, { force = opts.bang })
end, {
  bang = true,
  desc = "Initialize Omarchy Plugin project tasks; use ! to approve overwrite",
})
command("OmaDevTest", function()
  require("omarchy-plugin-dev.actions").test(0)
end, {
  desc = "Run the detected Omarchy Plugin project's test task",
})
command("OmaDevHotReload", function()
  require("omarchy-plugin-dev.actions").hot_reload(0)
end, {
  desc = "Check the selected build target and restart the Omarchy shell",
})
command("OmaDevBuild", function()
  require("omarchy-plugin-dev.actions").build(0)
end, {
  desc = "Check and test the selected target, then restart the Omarchy shell",
})
command("OmaDevHealth", function()
  require("omarchy-plugin-dev.actions").health()
end, {
  desc = "Run Neovim health checks for Omarchy Plugin development",
})

local group = vim.api.nvim_create_augroup("OmarchyPluginDev", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufFilePost", "FileType" }, {
  group = group,
  callback = function(event)
    require("omarchy-plugin-dev").attach(event.buf)
  end,
  desc = "Attach Omarchy Plugin project-local behavior",
})
vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(event)
    require("omarchy-plugin-dev.formatting").forget(event.buf)
    require("omarchy-plugin-dev.mappings").forget(event.buf)
  end,
  desc = "Forget deleted Omarchy Plugin buffers",
})
