local M = {}

local dashboard_win

local function status(value)
  return value and "available" or "missing"
end

local function executable_status(name)
  if vim.fn.executable(name) ~= 1 then
    return "missing - " .. name
  end
  local path = vim.fn.exepath(name)
  return "available - " .. (path ~= "" and path or name)
end

local function replace_line(bufnr, line, text)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, { text })
  vim.bo[bufnr].modifiable = false
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
  local lint_state, lint_detail = require("omarchy_plugin_dev.qmllint").status()
  local overseer_available = pcall(require, "overseer")
  local project = require("omarchy_plugin_dev.project")
  local tasks_data, tasks_error, tasks_exists = project.load_tasks(info.root)
  local test_state = project.test_state(info.root)
  local tasks_status = tasks_exists and (tasks_data and "valid" or "invalid") or "not initialized"
  if tasks_error then
    tasks_status = tasks_status .. " - " .. tasks_error
  end

  local lines = {
    "Project",
    "  root: " .. info.root,
    string.format("  manifest: recognized schema v1 (%s)", info.manifest.id),
    "  official validation: checking",
    "",
    "Tools",
    "  Overseer: " .. status(overseer_available),
    "  qml-language-server: " .. lsp_state .. " - " .. lsp_detail,
    "  omarchy: " .. executable_status(config.executables.omarchy),
    "  qmllint: " .. lint_state .. " - " .. lint_detail,
    "  jq: " .. executable_status(config.executables.jq),
    "  rsync: " .. executable_status(config.executables.rsync),
    "  logs: " .. executable_status(config.executables.journalctl) .. " (_COMM=quickshell)",
    "  project tasks: " .. tasks_status,
    "  test task: " .. test_state.label,
    "",
    "Build",
    "  Ctrl+B: check, deploy, restart shell",
    "  Ctrl+Shift+B: check, test, deploy, restart shell",
    "",
    "Actions",
    "  h  Build and restart      b  Test, build, restart",
    "  t  Test                  v  Health",
    "  p  Project tasks         i  Initialize project",
    "  e  Edit tasks.json",
    "  q  Close",
  }

  local actions = require("omarchy_plugin_dev.actions")
  local dashboard_buf, dashboard_window = M.open_text("Omarchy Plugin Dev", lines, {
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
      p = function()
        actions.tasks(bufnr)
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
  project.external_validate_async(info.root, function(valid, detail)
    local validation_status = valid and "passed" or "failed"
    if detail then
      validation_status = validation_status .. " - " .. detail:gsub("\n", " | ")
    end
    replace_line(dashboard_buf, 4, "  official validation: " .. validation_status)
  end)
  return dashboard_buf, dashboard_window
end

return M
