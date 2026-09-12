local M = {}

M.name = "omarchy_plugin_dev"

local enabled = false

local function candidates()
  local configured = require("omarchy_plugin_dev.config").get().executables.qml_language_server
  if configured ~= "auto" then
    return { configured }
  end
  return {
    "/usr/lib/qt6/bin/qmlls",
    "/usr/bin/qmlls",
    "qmlls",
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

function M.claim(bufnr)
  if not M.available() then
    return false
  end
  local info = require("omarchy_plugin_dev.project").detect(bufnr)
  if not info then
    return false
  end

  local detached = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == "qmlls" then
      vim.lsp.buf_detach_client(bufnr, client.id)
      local namespace = vim.lsp.diagnostic.get_namespace(client.id)
      vim.diagnostic.reset(namespace, bufnr)
      detached = true
    end
  end
  return detached
end

function M.setup()
  if vim.fn.has("nvim-0.11") ~= 1 then
    return false, "Neovim 0.11 or newer is required for native LSP configuration"
  end

  local executable = M.executable()
  local cmd = { executable or "qmlls", "-E" }
  local import_paths, import_error = require("omarchy_plugin_dev.qml").import_paths()
  for _, import_path in ipairs(import_paths) do
    vim.list_extend(cmd, { "-I", import_path })
  end
  vim.lsp.config(M.name, {
    cmd = cmd,
    filetypes = { "qml" },
    on_attach = function(client)
      local diagnostics = require("omarchy_plugin_dev.config").get().diagnostics
      if diagnostics ~= false then
        local namespace = vim.lsp.diagnostic.get_namespace(client.id)
        vim.diagnostic.config(diagnostics, namespace)
      end
    end,
    root_dir = M.root_dir,
  })

  local group = vim.api.nvim_create_augroup("OmarchyPluginDevLsp", { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(event)
      local client = event.data and vim.lsp.get_client_by_id(event.data.client_id)
      if client and client.name == "qmlls" then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(event.buf) then
            M.claim(event.buf)
          end
        end)
      end
    end,
    desc = "Keep Omarchy Plugin buffers on their project-aware QML server",
  })

  if import_error then
    vim.notify_once(import_error, vim.log.levels.WARN, { title = "Omarchy Plugin Dev" })
  end

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
