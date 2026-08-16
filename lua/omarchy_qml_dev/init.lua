local M = {}

local loaded = false

function M.attach(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return false
  end
  if vim.bo[bufnr].filetype ~= "qml" then
    require("omarchy_qml_dev.mappings").detach(bufnr)
    return false
  end

  local info = require("omarchy_qml_dev.project").detect(bufnr)
  if not info then
    require("omarchy_qml_dev.mappings").detach(bufnr)
    vim.b[bufnr].omarchy_qml_dev_root = nil
    return false
  end
  vim.b[bufnr].omarchy_qml_dev_root = info.root
  require("omarchy_qml_dev.mappings").attach(bufnr)
  if not require("omarchy_qml_dev.lsp").available() then
    vim.notify_once(
      require("omarchy_qml_dev.lsp").installation_message(),
      vim.log.levels.WARN,
      { title = "Omarchy QML Dev" }
    )
  end
  return true
end

function M.setup(opts)
  require("omarchy_qml_dev.config").setup(opts)
  require("omarchy_qml_dev.lsp").setup()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.attach(bufnr)
    end
  end
end

local function command(name, callback, opts)
  opts = vim.tbl_extend("force", {
    desc = "Omarchy QML development action",
    force = false,
    nargs = 0,
  }, opts or {})
  vim.api.nvim_create_user_command(name, callback, opts)
end

function M._load()
  if loaded then
    return
  end
  loaded = true
  local actions = require("omarchy_qml_dev.actions")

  command("OmaDev", function()
    actions.dashboard(0)
  end, {
    desc = "Open the Omarchy QML project dashboard",
  })
  command("OmaDevInit", function(opts)
    actions.init_project(0, { force = opts.bang })
  end, {
    bang = true,
    desc = "Initialize Omarchy QML project tasks; use ! to approve overwrite",
  })
  command("OmaDevTest", function()
    actions.test(0)
  end, {
    desc = "Run the detected Omarchy QML project's test task",
  })
  command("OmaDevHotReload", function()
    actions.hot_reload(0)
  end, {
    desc = "Validate, deploy, and hot reload the Omarchy QML plugin",
  })
  command("OmaDevRebuild", function()
    actions.rebuild(0)
  end, {
    desc = "Cleanly rebuild the plugin and restart the shell once",
  })
  command("OmaDevHealth", function()
    actions.health()
  end, {
    desc = "Run Neovim health checks for Omarchy QML development",
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufFilePost", "FileType" }, {
    group = vim.api.nvim_create_augroup("OmarchyQmlDev", { clear = true }),
    callback = function(event)
      M.attach(event.buf)
    end,
    desc = "Attach Omarchy QML project-local behavior",
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = "OmarchyQmlDev",
    callback = function(event)
      require("omarchy_qml_dev.mappings").forget(event.buf)
    end,
    desc = "Forget deleted Omarchy QML buffers",
  })
end

return M
