local M = {}

local function executable_path(executable)
  if vim.fn.executable(executable) ~= 1 then
    return nil
  end
  local path = vim.fn.exepath(executable)
  return path ~= "" and path or executable
end

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

  local config = require("omarchy_plugin_dev.config").get()
  for _, requirement in ipairs({
    { name = "omarchy", executable = config.executables.omarchy },
    { name = "jq", executable = config.executables.jq },
    { name = "rsync", executable = config.executables.rsync },
  }) do
    local path = executable_path(requirement.executable)
    if path then
      vim.health.ok(requirement.name .. " is available at " .. path)
    else
      vim.health.error(requirement.name .. " is required for build tasks")
    end
  end

  local lint_state, lint_detail, lint_info = require("omarchy_plugin_dev.qmllint").status()
  if lint_state == "missing" then
    vim.health.error(lint_detail)
  elseif lint_info.major and lint_info.major < 6 then
    vim.health.warn("qmllint is available at " .. lint_detail)
  else
    vim.health.ok("qmllint is available at " .. lint_detail)
  end

  local lsp = require("omarchy_plugin_dev.lsp")
  if lsp.available() then
    vim.health.ok("qmlls is available at " .. lsp.executable())
  else
    vim.health.warn(lsp.installation_message())
  end
end

return M
