local M = {}

M.name = "omarchy_plugin_dev"

local enabled = false
local javascript_clients = {
  ts_ls = true,
  tsserver = true,
  ["typescript-tools"] = true,
  vtsls = true,
}

local function stop_if_unused(client)
  vim.defer_fn(function()
    if next(client.attached_buffers) then
      return
    end
    if not (type(client.is_stopped) == "function" and client:is_stopped()) then
      client:stop()
    end
    vim.defer_fn(function()
      if not next(client.attached_buffers) and client.rpc and client.rpc.terminate then
        pcall(client.rpc.terminate)
      end
    end, 1000)
  end, 100)
end

local function detach(client, bufnr)
  vim.lsp.buf_detach_client(bufnr, client.id)
  local namespace = vim.lsp.diagnostic.get_namespace(client.id)
  vim.diagnostic.reset(namespace, bufnr)
  stop_if_unused(client)
end

local function candidates()
  local configured = require("omarchy-plugin-dev.config").get().executables.qml_language_server
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
  local info = require("omarchy-plugin-dev.project").detect_file(bufnr)
  if info then
    on_dir(info.root)
  end
end

function M.claim(bufnr)
  if not M.available() then
    return false
  end
  local info = require("omarchy-plugin-dev.project").detect_file(bufnr)
  if not info then
    return false
  end

  local detached = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local generic_javascript = vim.bo[bufnr].filetype == "qmljs" and javascript_clients[client.name]
    if client.name == "qmlls" or generic_javascript then
      detach(client, bufnr)
      detached = true
    end
  end
  return detached
end

function M.release(bufnr)
  local detached = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = M.name })) do
    detach(client, bufnr)
    detached = true
  end
  return detached
end

function M.setup()
  if vim.fn.has("nvim-0.11") ~= 1 then
    return false, "Neovim 0.11 or newer is required for native LSP configuration"
  end

  local executable = M.executable()
  local cmd = { executable or "qmlls", "--no-cmake-calls", "-E" }
  local import_paths, import_error = require("omarchy-plugin-dev.qml").import_paths()
  if import_error then
    if enabled then
      vim.lsp.enable(M.name, false)
      enabled = false
    end
    vim.notify_once(import_error, vim.log.levels.ERROR, { title = "Omarchy Plugin Dev" })
    return false, import_error
  end
  for _, import_path in ipairs(import_paths) do
    vim.list_extend(cmd, { "-I", import_path })
  end
  vim.lsp.config(M.name, {
    cmd = cmd,
    filetypes = { "qml", "qmljs" },
    on_attach = function(client)
      local diagnostics = require("omarchy-plugin-dev.config").get().diagnostics
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
