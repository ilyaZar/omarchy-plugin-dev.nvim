local M = {}

function M.check()
  vim.health.start("omarchy-plugin-dev.nvim")
  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim 0.11 or newer")
  else
    vim.health.error("Neovim 0.11 or newer is required")
  end

  if pcall(require, "overseer") then
    vim.health.ok("overseer.nvim is available")
  else
    vim.health.error("overseer.nvim is required for tasks")
  end

  local lsp = require("omarchy_plugin_dev.lsp")
  if lsp.available() then
    vim.health.ok("qmlls is available at " .. lsp.executable())
  else
    vim.health.warn(lsp.installation_message())
  end
end

return M
