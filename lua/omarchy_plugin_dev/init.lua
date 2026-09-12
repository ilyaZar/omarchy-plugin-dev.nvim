local M = {}

function M.attach(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return false
  end
  if vim.bo[bufnr].filetype ~= "qml" then
    require("omarchy_plugin_dev.mappings").detach(bufnr)
    return false
  end

  local info = require("omarchy_plugin_dev.project").detect(bufnr)
  if not info then
    require("omarchy_plugin_dev.mappings").detach(bufnr)
    vim.b[bufnr].omarchy_plugin_dev_root = nil
    return false
  end
  vim.b[bufnr].omarchy_plugin_dev_root = info.root
  require("omarchy_plugin_dev.mappings").attach(bufnr)
  require("omarchy_plugin_dev.lsp").claim(bufnr)
  if not require("omarchy_plugin_dev.lsp").available() then
    vim.notify_once(
      require("omarchy_plugin_dev.lsp").installation_message(),
      vim.log.levels.WARN,
      { title = "Omarchy Plugin Dev" }
    )
  end
  return true
end

---@param opts? OmarchyPluginDevOptions
function M.setup(opts)
  require("omarchy_plugin_dev.config").setup(opts)
  require("omarchy_plugin_dev.lsp").setup()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.attach(bufnr)
    end
  end
end

return M
