local M = {}

M.name = "omarchy_plugin_dev"

local enabled = false

local function candidates()
  local configured = require("omarchy_plugin_dev.config").get().executables.qml_language_server
  if configured ~= "auto" then
    return { configured }
  end
  return {
    "qmlls",
    "/usr/lib/qt6/bin/qmlls",
    vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "qmlls"),
  }
end

function M.executable()
  for _, candidate in ipairs(candidates()) do
    if vim.fn.executable(candidate) == 1 then
      return vim.fn.exepath(candidate) ~= "" and vim.fn.exepath(candidate) or candidate
    end
  end
end

function M.available()
  return M.executable() ~= nil
end

function M.installation_message()
  return "qmlls is missing; install qt6-declarative or the Mason package qmlls"
end

function M.root_dir(bufnr, on_dir)
  local info = require("omarchy_plugin_dev.project").detect(bufnr)
  if info then
    on_dir(info.root)
  end
end

function M.setup()
  if vim.fn.has("nvim-0.11") ~= 1 then
    return false, "Neovim 0.11 or newer is required for native LSP configuration"
  end

  local executable = M.executable()
  local cmd = { executable or "qmlls", "-E" }
  for _, import_path in ipairs(require("omarchy_plugin_dev.config").get().qml_import_paths) do
    vim.list_extend(cmd, { "-I", import_path })
  end
  vim.lsp.config(M.name, {
    cmd = cmd,
    filetypes = { "qml" },
    root_dir = M.root_dir,
  })

  if executable then
    vim.lsp.enable(M.name)
    enabled = true
    return true
  end
  if enabled then
    vim.lsp.enable(M.name, false)
    enabled = false
  end
  return false, M.installation_message()
end

function M.status(bufnr)
  bufnr = bufnr or 0
  if not M.available() then
    return "missing", M.installation_message()
  end
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = M.name })
  if #clients > 0 then
    return "running", string.format("running as client %d", clients[1].id)
  end
  if enabled then
    return "available", "available; starts only in detected Omarchy Plugin buffers"
  end
  return "available", "available; run setup() to enable it"
end

return M
