---@diagnostic disable: duplicate-set-field
local config = require("omarchy-plugin-dev.config")
local project = require("omarchy-plugin-dev.project")
local ui = require("omarchy-plugin-dev.ui")
local saved_config = vim.deepcopy(config.get())
local saved_actions = package.loaded["omarchy-plugin-dev.actions"]
local saved_validate = project.external_validate_async
local saved_test_state = project.test_state
local saved_inspect = project.inspect
local lsp = require("omarchy-plugin-dev.lsp")
local saved_lsp_status = lsp.status
local columns, lines = vim.o.columns, vim.o.lines
local pending = {}
local calls = {}
local source_buf = vim.api.nvim_get_current_buf()
local info =
  { root = "/tmp/dashboard fixture", manifest = { id = "dev.dashboard", schemaVersion = 1 } }
local expected = {
  h = "hot_reload",
  b = "build",
  t = "test",
  v = "health",
  p = "tasks",
  i = "init_project",
  e = "edit_tasks",
  c = "edit_config",
}

package.loaded["omarchy-plugin-dev.actions"] = {}
for _, method in pairs(expected) do
  package.loaded["omarchy-plugin-dev.actions"][method] = function(bufnr)
    calls[#calls + 1] = { method, bufnr }
  end
end
project.external_validate_async = function(_, callback)
  pending[#pending + 1] = callback
end
project.test_state = function()
  return { kind = "configured", label = "configured - true", tasks_exists = true }
end
project.inspect = function(bufnr)
  assert(bufnr == source_buf, "inspection lost the source buffer")
  return vim.deepcopy(info)
end
lsp.status = function()
  return "running", "running as client 2"
end

local function open_dashboard()
  local buf, win = ui.dashboard(source_buf)
  assert(buf and win, "could not open dashboard fixture")
  return buf, win
end

local function key(bufnr, lhs)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if mapping.lhs == lhs then
      return mapping.callback
    end
  end
  error("missing dashboard key: " .. lhs)
end

vim.o.columns, vim.o.lines = 120, 40
config.setup({
  mappings = { hot_reload = "<F5>", build = false },
  logs = { match = "_COMM=custom" },
})
local buf, win = open_dashboard()
local function text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end
local function selected_text(bufnr, window)
  local cursor = vim.api.nvim_win_get_cursor(window)
  assert(cursor[2] == 0, "selection cursor moved horizontally")
  return vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
end
local function check_layout(bufnr)
  local ns = vim.api.nvim_get_namespaces()["omarchy-plugin-dev.dashboard"]
  local detail_column, action_column
  local rows = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  assert(rows[#rows] == "", "dashboard has no bottom padding")
  for index, line in ipairs(rows) do
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { index - 1, 0 }, { index - 1, -1 }, {
      details = true,
    })
    if line:match("^  [%w-][%w %-]*:  ") then
      assert(marks[1][4].hl_group == "Normal", "field label is dimmed")
      if #marks == 3 then
        local detail = marks[3]
        detail_column = detail_column or detail[3]
        assert(detail[3] == detail_column, "field explanations are not aligned")
        assert(detail[4].hl_group == "Comment", "field explanation is not dimmed")
        assert(line:sub(detail[3] + 1, detail[3] + 2) == "  ", "detail separator is not spaces")
      end
    elseif line:match("^  %[%a%]") then
      local detail = marks[#marks]
      action_column = action_column or detail[3]
      assert(detail[3] == action_column, "action explanations are not aligned")
      assert(detail[4].hl_group == "Comment", "action explanation is not dimmed")
      assert(marks[2][4].hl_group == "Normal", "action label is dimmed")
    end
  end
end
local function check_tab_style(bufnr, active)
  local ns = vim.api.nvim_get_namespaces()["omarchy-plugin-dev.dashboard"]
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { 0, -1 }, { details = true })
  assert(#marks == 6, "tab shortcuts and labels are not separate")
  for index = 1, 3 do
    local shortcut = marks[index * 2 - 1][4].hl_group
    assert(shortcut == (index == active and "DiagnosticWarn" or "DiagnosticInfo"))
    assert(marks[index * 2][4].hl_group == "Normal", "tab label is not Normal")
  end
end

local function check_manifest_style(bufnr, state, status_group, detail_group)
  local ns = vim.api.nvim_get_namespaces()["omarchy-plugin-dev.dashboard"]
  for index, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:match("^  manifest:") then
      assert(line:find(state, 1, true), "wrong manifest status")
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { index - 1, 0 }, { index - 1, -1 }, {
        details = true,
      })
      assert(marks[2][4].hl_group == status_group, "wrong manifest status color")
      assert(marks[3][4].hl_group == detail_group, "wrong manifest detail color")
      return
    end
  end
  error("manifest row is missing")
end
local contents = text(buf)
assert(contents:find("[1] Build  [2] Status  [3] Settings", 1, true), "dashboard tabs changed")
check_tab_style(buf, 1)
assert(contents:find("  Actions ", 1, true), "Build is not the initial tab")
assert(selected_text(buf, win):find("[h]", 1, true), "Build did not select its first action")
key(buf, "2")()
contents = text(buf)
check_tab_style(buf, 2)
check_layout(buf)
check_manifest_style(buf, "recognized", "DiagnosticOk", "Comment")
assert(contents:find("schema v1 (dev.dashboard)", 1, true), "schema detail was lost")
assert(contents:find("running as client 2", 1, true), "LSP detail was lost")
assert(contents:match("configured%s+true"), "test command detail was lost")
assert(selected_text(buf, win):find("root:", 1, true), "status did not select its first row")
key(buf, "<CR>")()
assert(#calls == 0 and vim.api.nvim_win_is_valid(win), "status Enter executed an action")
key(buf, "j")()
assert(selected_text(buf, win):find("manifest:", 1, true), "j did not select the next field")
key(buf, "<Down>")()
key(buf, "j")()
assert(selected_text(buf, win):find("Overseer:", 1, true), "navigation did not skip headings")
key(buf, "<Up>")()
assert(selected_text(buf, win):find("official validation:", 1, true), "up did not skip headings")
local validation_cursor = vim.api.nvim_win_get_cursor(win)
pending[#pending](true)
assert(
  vim.deep_equal(validation_cursor, vim.api.nvim_win_get_cursor(win)),
  "validation moved selection"
)
vim.api.nvim_win_set_cursor(win, { 1, 4 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
assert(selected_text(buf, win):find("root:", 1, true), "cursor escaped to a heading")
vim.api.nvim_win_set_cursor(win, { vim.api.nvim_win_get_cursor(win)[1], 5 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
assert(vim.api.nvim_win_get_cursor(win)[2] == 0, "horizontal movement was not constrained")
assert(contents:find("Project", 1, true) < contents:find("Tools", 1, true), "status order changed")
assert(not contents:find("[h]", 1, true), "status includes action rows")
assert(contents:find("_COMM=custom", 1, true), "dashboard ignores journal match")
key(buf, "1")()
check_layout(buf)
contents = text(buf)
assert(
  contents:find("Open .omarchy-plugin-dev/task-config.json", 1, true),
  "edit target is missing"
)
assert(contents:find("confirm before replacing", 1, true), "initialization explanation is missing")
assert(contents:find("Show configuration help", 1, true), "settings help fallback is missing")
assert(contents:find("  Actions ", 1, true), "build lost the Actions section")
assert(not contents:find("Build keybindings", 1, true), "build still includes settings")
assert(not contents:find("_COMM=custom", 1, true), "build includes tool rows")
assert(contents:find("Run the plugin's health check", 1, true), "health description is unclear")
assert(selected_text(buf, win):find("[h]", 1, true), "build did not select its first row")
key(buf, "G")()
assert(selected_text(buf, win):find("[c]", 1, true), "build did not select its last action")
key(buf, "j")()
assert(selected_text(buf, win):find("[c]", 1, true), "build selection escaped its rows")
key(buf, "3")()
check_layout(buf)
assert(text(buf):find("Build keybindings", 1, true), "3 did not select settings")
assert(not text(buf):find("[h]", 1, true), "settings includes action rows")
assert(text(buf):find("<F5>", 1, true), "dashboard lost configured mapping")
assert(text(buf):find("disabled", 1, true), "dashboard hides disabled mapping")
assert(
  selected_text(buf, win):find("hot reload:", 1, true),
  "settings did not select its first row"
)
key(buf, "G")()
assert(selected_text(buf, win):find("build:", 1, true), "G did not select the last keybinding")
assert(selected_text(buf, win):find("Enter: settings help", 1, true), "build row has no edit hint")
key(buf, "j")()
assert(selected_text(buf, win):find("build:", 1, true), "selection moved past the last row")
key(buf, "k")()
assert(selected_text(buf, win):find("hot reload:", 1, true), "hot reload row is not selectable")
assert(
  selected_text(buf, win):find("Enter: settings help", 1, true),
  "hot reload row has no edit hint"
)
key(buf, "k")()
assert(selected_text(buf, win):find("hot reload:", 1, true), "selection moved into the heading")
key(buf, "<Tab>")()
assert(selected_text(buf, win):find("[h]", 1, true), "Tab did not wrap to Build")
key(buf, "<S-Tab>")()
assert(selected_text(buf, win):find("hot reload:", 1, true), "Shift-Tab did not wrap to Settings")
key(buf, "<S-Tab>")()
assert(selected_text(buf, win):find("root:", 1, true), "Shift-Tab did not select Status")
key(buf, "1")()
assert(text(buf) == contents, "1 did not restore Build")
key(buf, "gg")()
key(buf, "k")()
assert(selected_text(buf, win):find("[h]", 1, true), "selection moved before the first row")
for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  assert(not line:match("%[h%].-%[b%]"), "actions still share a row")
end
local selection_ns = vim.api.nvim_get_namespaces()["omarchy-plugin-dev.dashboard.selection"]
local marks = vim.api.nvim_buf_get_extmarks(buf, selection_ns, 0, -1, { details = true })
assert(#marks == 1 and marks[1][4].line_hl_group == "Visual", "selected row is not highlighted")
local footer = vim.api.nvim_win_get_config(win).footer
assert(footer, "dashboard footer is missing")
local footer_text = table.concat(vim.tbl_map(function(chunk)
  return chunk[1]
end, footer))
assert(
  footer_text:find("[Tab] switch  [r]efresh  [q/Esc]", 1, true),
  "refresh footer order changed"
)
assert(not vim.bo[buf].modifiable, "dashboard is editable")
assert(vim.wo[win].wrap, "dashboard truncates full paths and errors")
local ns = vim.api.nvim_get_namespaces()["omarchy-plugin-dev.dashboard"]
assert(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) > 0, "dashboard has no highlighting")
pending[#pending](false, "validation failed\nexample detail")
assert(text(buf) == contents, "background validation corrupted the actions tab")
key(buf, "2")()
contents = text(buf)
check_layout(buf)
assert(contents:find("validation failed | example detail", 1, true), "validation detail was lost")
key(buf, "1")()
assert(text(buf):find("[h]", 1, true), "1 did not select Build")
key(buf, "3")()
assert(text(buf):find("Build keybindings", 1, true), "3 did not select settings")
key(buf, "2")()
assert(text(buf) == contents, "2 did not restore Status")
assert(#pending == 1, "switching tabs reran validation")
key(buf, "q")()
assert(not vim.api.nvim_win_is_valid(win), "q did not close dashboard")

vim.o.columns, vim.o.lines = 60, 20
config.setup({ mappings = false })
for _, tab in ipairs({ "1", "2", "3" }) do
  for lhs, method in pairs(expected) do
    local action_buf, action_win = open_dashboard()
    key(action_buf, tab)()
    assert(vim.api.nvim_win_get_width(action_win) <= 56, "dashboard exceeds narrow editor")
    for _, line in ipairs(vim.api.nvim_buf_get_lines(action_buf, 0, -1, false)) do
      assert(not line:match("%[h%].-%[b%]"), "narrow dashboard did not stack actions")
    end
    key(action_buf, lhs)()
    assert(not vim.api.nvim_win_is_valid(action_win), "action did not close dashboard")
    assert(calls[#calls][1] == method and calls[#calls][2] == source_buf, "action routing changed")
    pending[#pending](true)
  end
end

for index, method in ipairs({
  "hot_reload",
  "build",
  "test",
  "health",
  "tasks",
  "init_project",
  "edit_tasks",
  "edit_config",
  "edit_config",
  "edit_config",
}) do
  local action_buf, action_win = open_dashboard()
  key(action_buf, index > 8 and "3" or "1")()
  local row = index > 8 and index - 8 or index
  for _ = 2, row do
    key(action_buf, "j")()
  end
  key(action_buf, "<CR>")()
  assert(not vim.api.nvim_win_is_valid(action_win), "Enter did not close dashboard")
  assert(calls[#calls][1] == method and calls[#calls][2] == source_buf, "Enter ran wrong action")
end

config.setup({ config_file = "lua/my settings.lua" })
local settings_buf = open_dashboard()
key(settings_buf, "1")()
assert(
  text(settings_buf):find("Open my settings.lua", 1, true),
  "settings file explanation is missing"
)
key(settings_buf, "3")()
local hint_count = 0
for _, line in ipairs(vim.api.nvim_buf_get_lines(settings_buf, 0, -1, false)) do
  if line:find("Enter: edit keybindings", 1, true) then
    assert(line:match("^  [%w ]+:"), "edit hint is not on a keybinding row")
    hint_count = hint_count + 1
  end
end
assert(hint_count == 2, "each keybinding row needs its own edit hint")
key(settings_buf, "G")()
key(settings_buf, "<CR>")()
assert(calls[#calls][1] == "edit_config", "build row Enter did not open settings")

local old_buf = open_dashboard()
local late_validation = pending[#pending]
local new_buf, new_win = open_dashboard()
assert(not vim.api.nvim_buf_is_valid(old_buf), "reopening retained old dashboard")
late_validation(false, "stale result")
contents = table.concat(vim.api.nvim_buf_get_lines(new_buf, 0, -1, false), "\n")
assert(not contents:find("stale result", 1, true), "late validation changed new dashboard")
key(new_buf, "<Esc>")()
assert(not vim.api.nvim_win_is_valid(new_win), "escape did not close dashboard")

for _, schema in ipairs({ 2, 42, "1", false }) do
  info.manifest.schemaVersion = schema
  local unsupported_buf, unsupported_win = open_dashboard()
  key(unsupported_buf, "2")()
  check_manifest_style(unsupported_buf, "unsupported", "DiagnosticError", "Normal")
  pending[#pending](false, "unsupported schema")
  check_manifest_style(unsupported_buf, "unsupported", "DiagnosticError", "Normal")
  vim.api.nvim_win_close(unsupported_win, true)
end

vim.o.columns, vim.o.lines = columns, lines
project.external_validate_async = saved_validate
project.test_state = saved_test_state
project.inspect = saved_inspect
lsp.status = saved_lsp_status
package.loaded["omarchy-plugin-dev.actions"] = saved_actions
---@diagnostic disable-next-line: param-type-mismatch
config.setup(saved_config)
