local M = {}

local dashboard_win

local function status(value)
  return value and "available" or "missing"
end

local function executable(name)
  return vim.fn.executable(name) == 1
end

function M.open_text(title, lines, opts)
  opts = opts or {}
  if dashboard_win and vim.api.nvim_win_is_valid(dashboard_win) then
    vim.api.nvim_win_close(dashboard_win, true)
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].filetype = opts.filetype or "omarchy-plugin-dev"
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  local width = math.max(40, math.min(opts.width or 76, vim.o.columns - 4))
  local height = math.max(8, math.min(#lines, vim.o.lines - 4))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))
  dashboard_win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
  })

  local function close()
    if dashboard_win and vim.api.nvim_win_is_valid(dashboard_win) then
      vim.api.nvim_win_close(dashboard_win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = bufnr, desc = "Close Omarchy Plugin window" })
  vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, desc = "Close Omarchy Plugin window" })

  for lhs, action in pairs(opts.actions or {}) do
    vim.keymap.set("n", lhs, function()
      close()
      action()
    end, { buffer = bufnr, desc = "Omarchy Plugin: " .. lhs, silent = true })
  end
  return bufnr, dashboard_win
end

function M.dashboard(info, bufnr)
  local config = require("omarchy_plugin_dev.config").get()
  local lsp_state, lsp_detail = require("omarchy_plugin_dev.lsp").status(bufnr)
  local reload = require("omarchy_plugin_dev.reload").capability()
  local overseer_available = pcall(require, "overseer")
  local tasks_data, tasks_error, tasks_exists =
    require("omarchy_plugin_dev.project").load_tasks(info.root)
  local tasks_status = tasks_exists and (tasks_data and "valid" or "invalid") or "not initialized"

  local lines = {
    "Project",
    "  root: " .. info.root,
    string.format("  manifest: valid schema v1 (%s)", info.manifest.id),
    "",
    "Tools",
    "  Overseer: " .. status(overseer_available),
    "  qml-language-server: " .. lsp_state .. " - " .. lsp_detail,
    "  omarchy: " .. status(executable(config.executables.omarchy)),
    "  qmllint: " .. status(executable(config.executables.qmllint)),
    "  logs: "
      .. status(executable(config.executables.journalctl))
      .. " (journal _COMM=quickshell)",
    "  project tasks: " .. tasks_status,
    "",
    "Reload",
    string.format("  %s: %s", reload.label, reload.detail),
    "",
    "Actions",
    "  h  Hot reload            b  Clean rebuild",
    "  t  Test                  v  Health",
    "  i  Initialize project    e  Edit tasks.json",
    "  q  Close",
  }
  if tasks_error then
    table.insert(lines, 12, "  tasks error: " .. tasks_error)
  end

  local actions = require("omarchy_plugin_dev.actions")
  return M.open_text("Omarchy Plugin Dev", lines, {
    actions = {
      t = function()
        actions.test(bufnr)
      end,
      h = function()
        actions.hot_reload(bufnr)
      end,
      b = function()
        actions.rebuild(bufnr)
      end,
      i = function()
        actions.init_project(bufnr)
      end,
      e = function()
        actions.edit_tasks(bufnr)
      end,
      v = function()
        actions.health()
      end,
    },
  })
end

return M
