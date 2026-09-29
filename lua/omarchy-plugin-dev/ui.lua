local M = {}

local dashboard_win
local namespace = vim.api.nvim_create_namespace("omarchy-plugin-dev.dashboard")
local selection_namespace = vim.api.nvim_create_namespace("omarchy-plugin-dev.dashboard.selection")

local action_items = {
  { "h", "Build and restart", "hot_reload", "Check, deploy, then restart the shell" },
  { "b", "Test, build, restart", "build", "Check, test, deploy, then restart the shell" },
  { "t", "Test", "test", "Run the configured project test" },
  { "v", "Health", "health", "Open the plugin's health report" },
  { "p", "Project tasks", "tasks", "Choose a project task to run" },
  {
    "i",
    "Initialize project",
    "init_project",
    "Create task-config.json; confirm before replacing",
  },
  { "e", "Edit task configuration", "edit_tasks" },
  { "c", "Plugin settings", "edit_config" },
}

local function column(value, width)
  return value .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(value), 1))
end

local function field(label, value, group, detail, action)
  return {
    selectable = true,
    action = action,
    value = value,
    { "  " .. column(label .. ":", 22), "Normal" },
    { value, group or "Normal" },
    { detail and "  " .. detail or "", "Comment" },
  }
end

local function align_details(rows)
  local width = 0
  for _, row in ipairs(rows) do
    if row.value and row[3][1] ~= "" then
      width = math.max(width, vim.fn.strdisplaywidth(row.value))
    end
  end
  for _, row in ipairs(rows) do
    if row.value and row[3][1] ~= "" then
      row[2][1] = column(row.value, width + 2)
    end
  end
end

local function status_group(value)
  if value == "missing" or value == "failed" or value == "invalid" or value == "unavailable" then
    return "DiagnosticError"
  end
  if
    value == "available"
    or value == "running"
    or value == "passed"
    or value == "configured"
    or value == "valid"
  then
    return "DiagnosticOk"
  end
  return "DiagnosticWarn"
end

local function executable_row(label, name)
  local available = vim.fn.executable(name) == 1
  local state = available and "available" or "missing"
  local path = available and vim.fn.exepath(name) or name
  return field(label, state, status_group(state), path ~= "" and path or name)
end

local function mapping_label(mappings, name)
  if not mappings or mappings.enabled == false or not mappings[name] then
    return "disabled"
  end
  return mappings[name]:gsub("^<C%-S%-(.)>$", "Ctrl+Shift+%1"):gsub("^<C%-(.)>$", "Ctrl+%1")
end

local function draw_row(bufnr, line, chunks)
  local parts = {}
  for _, chunk in ipairs(chunks) do
    parts[#parts + 1] = chunk[1]
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, { table.concat(parts) })
  vim.bo[bufnr].modifiable = false
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, line - 1, line)
  local col = 0
  for _, chunk in ipairs(chunks) do
    local next_col = col + #chunk[1]
    if next_col > col then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, line - 1, col, {
        end_col = next_col,
        hl_group = chunk[2] or "Normal",
      })
    end
    col = next_col
  end
end

local function dashboard_rows(info, bufnr, width)
  local config = require("omarchy-plugin-dev.config").get()
  local project = require("omarchy-plugin-dev.project")
  local rows = {}
  local function section(label, hint)
    if #rows > 0 then
      rows[#rows + 1] = {}
    end
    hint = hint and " " .. hint .. " " or ""
    rows[#rows + 1] = {
      { "  " .. label .. " ", { "DiagnosticOk", "Bold" } },
      { hint, "Comment" },
      { string.rep("-", math.max(width - #label - #hint - 5, 0)), "Comment" },
    }
  end
  local function add(row)
    rows[#rows + 1] = row
  end

  section("Project")
  add(field("root", info.root))
  add(field("manifest", "recognized schema v1 (" .. info.manifest.id .. ")", "DiagnosticInfo"))
  add(field("official validation", "checking", "DiagnosticWarn"))
  local validation_line = #rows

  section("Tools")
  local overseer_available = pcall(require, "overseer")
  local overseer_state = overseer_available and "available" or "missing"
  add(field("Overseer", overseer_state, status_group(overseer_state)))
  local lsp_state, lsp_detail = require("omarchy-plugin-dev.lsp").status(bufnr)
  add(field("qml-language-server", lsp_state, status_group(lsp_state), lsp_detail))
  add(executable_row("omarchy", config.executables.omarchy))
  local lint_state, lint_detail = require("omarchy-plugin-dev.qmllint").status()
  add(field("qmllint", lint_state, status_group(lint_state), lint_detail))
  add(executable_row("jq", config.executables.jq))
  add(executable_row("rsync", config.executables.rsync))
  local logs = executable_row("logs", config.executables.journalctl)
  logs[3][1] = logs[3][1] .. " (" .. config.logs.match .. ")"
  add(logs)
  local tasks_data, tasks_error, tasks_exists = project.load_tasks(info.root)
  local tasks_status = tasks_exists and (tasks_data and "valid" or "invalid") or "not initialized"
  add(field("project tasks", tasks_status, status_group(tasks_status), tasks_error))
  local test_state = project.test_state(info.root)
  local test_label, test_detail = test_state.label:match("^(.-) %- (.*)$")
  add(
    field("test task", test_label or test_state.label, status_group(test_state.kind), test_detail)
  )
  align_details(rows)
  local overview = rows
  rows = {}

  section("Build", config.config_file and "Enter: edit keybindings" or "Enter: settings help")
  add(
    field(
      "hot reload",
      mapping_label(config.mappings, "hot_reload"),
      "DiagnosticInfo",
      "check, deploy, restart shell",
      "edit_config"
    )
  )
  add(
    field(
      "build",
      mapping_label(config.mappings, "build"),
      "DiagnosticInfo",
      "check, test, deploy, restart shell",
      "edit_config"
    )
  )

  align_details(rows)
  section("Actions")
  local label_width = 0
  for _, item in ipairs(action_items) do
    label_width = math.max(label_width, vim.fn.strdisplaywidth(item[2]))
  end
  for _, item in ipairs(action_items) do
    local detail = item[4]
    if item[3] == "edit_tasks" then
      detail = "Open .omarchy-plugin-dev/"
        .. vim.fs.basename(project.existing_tasks_path(info.root))
    elseif item[3] == "edit_config" then
      local path = require("omarchy-plugin-dev.config").user_config_path()
      detail = path and ("Open " .. vim.fs.basename(path)) or "Show configuration help"
    end
    add({
      action = item[3],
      { "  [" .. item[1] .. "]", "DiagnosticOk" },
      { " " .. column(item[2], label_width + 3), "Normal" },
      { detail, "Comment" },
    })
  end
  return { overview, rows }, validation_line
end

local function attach_selection(buf, win, activate)
  local items, selected = {}, 1
  local moving = false
  local function select(index)
    selected = math.max(1, math.min(#items, index))
    local item = items[selected]
    if not item then
      return
    end
    moving = true
    vim.api.nvim_win_set_cursor(win, { item.line, 0 })
    moving = false
    vim.api.nvim_buf_clear_namespace(buf, selection_namespace, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, selection_namespace, item.line - 1, 0, {
      line_hl_group = "Visual",
    })
  end
  local function map(keys, callback)
    for _, key in ipairs(keys) do
      vim.keymap.set("n", key, callback, { buffer = buf, silent = true })
    end
  end
  map({ "j", "<Down>" }, function()
    select(selected + vim.v.count1)
  end)
  map({ "k", "<Up>" }, function()
    select(selected - vim.v.count1)
  end)
  map({ "gg" }, function()
    select(1)
  end)
  map({ "G" }, function()
    select(#items)
  end)
  map({ "<CR>" }, function()
    local item = items[selected]
    if item and item.action then
      activate(item.action)
    end
  end)
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if moving or not vim.api.nvim_win_is_valid(win) then
        return
      end
      local line = vim.api.nvim_win_get_cursor(win)[1]
      local nearest, distance = 1, math.huge
      for index, item in ipairs(items) do
        local gap = math.abs(line - item.line)
        if gap < distance then
          nearest, distance = index, gap
        end
      end
      select(nearest)
    end,
  })
  return function(rows, overview)
    items = {}
    for line, row in ipairs(rows) do
      if row.action or (overview and row.selectable) then
        items[#items + 1] = { line = line + 2, action = row.action }
      end
    end
    select(1)
  end, function()
    select(selected)
  end
end

function M.dashboard(info, bufnr)
  if dashboard_win and vim.api.nvim_win_is_valid(dashboard_win) then
    vim.api.nvim_win_close(dashboard_win, true)
  end

  local width = math.max(1, math.min(100, math.floor(vim.o.columns * 0.84), vim.o.columns - 4))
  local views, validation_line = dashboard_rows(info, bufnr, width)
  local active_view = 1
  local height = math.max(1, math.min(math.max(#views[1], #views[2]) + 3, vim.o.lines - 4))
  local dashboard_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[dashboard_buf].bufhidden = "wipe"
  vim.bo[dashboard_buf].filetype = "omarchy-plugin-dev"
  local function render()
    local rows = {
      {
        { "  [1 Overview]", active_view == 1 and "DiagnosticWarn" or "Comment" },
        { "  [2 Actions]", active_view == 2 and "DiagnosticWarn" or "Comment" },
      },
      {},
    }
    vim.list_extend(rows, views[active_view])
    rows[#rows + 1] = {}
    vim.bo[dashboard_buf].modifiable = true
    vim.api.nvim_buf_clear_namespace(dashboard_buf, namespace, 0, -1)
    vim.api.nvim_buf_set_lines(
      dashboard_buf,
      0,
      -1,
      false,
      vim.tbl_map(function()
        return ""
      end, rows)
    )
    for line, chunks in ipairs(rows) do
      draw_row(dashboard_buf, line, chunks)
    end
  end
  render()

  local win = vim.api.nvim_open_win(dashboard_buf, true, {
    relative = "editor",
    border = "single",
    title = { { " Omarchy Plugin Dev ", "FloatTitle" } },
    title_pos = "center",
    footer = {
      { " [j/k]", "DiagnosticOk" },
      { " move  ", "Comment" },
      { "[Tab]", "DiagnosticOk" },
      { " switch  ", "Comment" },
      { "[q / Esc]", "DiagnosticOk" },
      { " close ", "Comment" },
    },
    footer_pos = "center",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
  })
  dashboard_win = win
  -- Keep full paths and failure details accessible rather than truncating them.
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].cursorline = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set(
      "n",
      lhs,
      close,
      { buffer = dashboard_buf, desc = "Close Omarchy Plugin window" }
    )
  end
  local actions = require("omarchy-plugin-dev.actions")
  local function activate(method)
    close()
    actions[method](bufnr)
  end
  local reset_selection, refresh_selection = attach_selection(dashboard_buf, win, activate)
  reset_selection(views[active_view], active_view == 1)
  for _, lhs in ipairs({ "<Tab>", "<S-Tab>", "1", "2" }) do
    vim.keymap.set("n", lhs, function()
      active_view = tonumber(lhs) or (3 - active_view)
      render()
      reset_selection(views[active_view], active_view == 1)
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = 1 })
      end)
    end, { buffer = dashboard_buf, desc = "Omarchy Plugin: switch dashboard tab", silent = true })
  end
  for _, item in ipairs(action_items) do
    vim.keymap.set("n", item[1], function()
      activate(item[3])
    end, { buffer = dashboard_buf, desc = "Omarchy Plugin: " .. item[2], silent = true })
  end

  require("omarchy-plugin-dev.project").external_validate_async(info.root, function(valid, detail)
    if not vim.api.nvim_buf_is_valid(dashboard_buf) then
      return
    end
    local state = valid and "passed" or "failed"
    views[1][validation_line] =
      field("official validation", state, status_group(state), detail and detail:gsub("\n", " | "))
    align_details(views[1])
    if active_view == 1 then
      for line, row in ipairs(views[1]) do
        draw_row(dashboard_buf, line + 2, row)
      end
      refresh_selection()
    end
  end)
  return dashboard_buf, win
end

return M
