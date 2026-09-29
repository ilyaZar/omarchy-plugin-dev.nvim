local M = {}

local group = vim.api.nvim_create_augroup("OmarchyPluginDevFormat", { clear = false })
local states = {}

local function clear(bufnr)
  vim.api.nvim_clear_autocmds({ group = group, buffer = bufnr })
end

function M.format(bufnr)
  bufnr = bufnr or 0
  local clients = vim.lsp.get_clients({
    bufnr = bufnr,
    name = require("omarchy-plugin-dev.lsp").name,
  })
  if #clients == 0 then
    return false
  end

  vim.lsp.buf.format({
    async = false,
    bufnr = bufnr,
    id = clients[1].id,
    timeout_ms = 3000,
  })
  return true
end

function M.attach(bufnr)
  bufnr = bufnr or 0
  clear(bufnr)
  if vim.bo[bufnr].filetype ~= "qml" then
    M.detach(bufnr)
    return false
  end

  if not states[bufnr] then
    states[bufnr] = {
      autoformat = vim.b[bufnr].autoformat,
      expandtab = vim.bo[bufnr].expandtab,
      shiftwidth = vim.bo[bufnr].shiftwidth,
      softtabstop = vim.bo[bufnr].softtabstop,
      tabstop = vim.bo[bufnr].tabstop,
    }
  end

  vim.bo[bufnr].expandtab = true
  vim.bo[bufnr].shiftwidth = 4
  vim.bo[bufnr].softtabstop = 4
  vim.bo[bufnr].tabstop = 4

  -- This plugin owns formatting for detected QML buffers so editor-wide hooks
  -- do not format the same buffer a second time.
  vim.b[bufnr].autoformat = false
  if not require("omarchy-plugin-dev.config").get().format_on_save then
    return true
  end

  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    buffer = bufnr,
    callback = function(event)
      M.format(event.buf)
    end,
    desc = "Format Omarchy Plugin QML with qmlls",
  })
  return true
end

function M.detach(bufnr)
  bufnr = bufnr or 0
  if vim.api.nvim_buf_is_valid(bufnr) then
    clear(bufnr)
    local state = states[bufnr]
    if state then
      vim.b[bufnr].autoformat = state.autoformat
      vim.bo[bufnr].expandtab = state.expandtab
      vim.bo[bufnr].shiftwidth = state.shiftwidth
      vim.bo[bufnr].softtabstop = state.softtabstop
      vim.bo[bufnr].tabstop = state.tabstop
    end
  end
  states[bufnr] = nil
end

function M.forget(bufnr)
  states[bufnr] = nil
end

return M
