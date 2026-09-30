---@diagnostic disable: duplicate-set-field
local dashboard = require("omarchy-plugin-dev.dashboard")
local project = require("omarchy-plugin-dev.project")
local collect, validate = dashboard.collect, project.external_validate_async
local columns, lines, scrolloff = vim.o.columns, vim.o.lines, vim.o.scrolloff
vim.o.columns, vim.o.lines, vim.o.scrolloff = 120, 60, 10
local pending
local snapshot = {
  info = {
    root = "/project/" .. string.rep("long-directory/", 8),
    manifest = { schemaVersion = 1, id = "dev.height" },
  },
  build_root = "/installed/project",
  options = { mappings = {} },
  tasks_path = "/project/.omarchy-plugin-dev/task-config.json",
  validation = { state = "checking" },
  sources = { entries = {}, detail = "Select a target" },
  tools = {},
}
for _, name in ipairs({
  "Overseer",
  "qml-language-server",
  "omarchy",
  "qmllint",
  "jq",
  "rsync",
  "logs",
  "project tasks",
  "test task",
}) do
  snapshot.tools[#snapshot.tools + 1] = { name, "available", "available", "/tools/" .. name }
end
dashboard.collect = function()
  return vim.deepcopy(snapshot)
end
project.external_validate_async = function(_, callback)
  pending = callback
end
local function key(buf, lhs)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if mapping.lhs == lhs then
      mapping.callback()
      return
    end
  end
  error("missing key " .. lhs)
end
local function fits(buf, win)
  local rendered = vim.api.nvim_win_text_height(win, {}).all
  assert(vim.api.nvim_win_get_height(win) >= rendered, "wrapped Status rows need scrolling")
  assert(vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] == "", "footer spacing is missing")
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  assert(view.topline == 1 and view.skipcol == 0, "dashboard scrolled despite fitting")
end
local buf, win = require("omarchy-plugin-dev.ui").dashboard()
assert(buf and win, "dashboard did not open")
key(buf, "2")
fits(buf, win)
local before = vim.api.nvim_win_get_height(win)
key(buf, "G")
local cursor = vim.api.nvim_win_get_cursor(win)
pending(false, "Validation failed: " .. string.rep("a directory with spaces/", 16))
assert(vim.api.nvim_win_get_height(win) > before, "async validation did not grow the popup")
assert(vim.deep_equal(cursor, vim.api.nvim_win_get_cursor(win)), "resizing moved the selection")
fits(buf, win)
local height = vim.api.nvim_win_get_height(win)
key(buf, "1")
assert(vim.api.nvim_win_get_height(win) == height, "switching tabs shrank the popup")
key(buf, "2")
key(buf, "G")
fits(buf, win)
key(buf, "q")
vim.o.lines = 14
buf, win = require("omarchy-plugin-dev.ui").dashboard()
assert(buf and win, "small dashboard did not open")
key(buf, "2")
pending(false, string.rep("very long validation detail ", 40))
assert(vim.api.nvim_win_get_height(win) <= vim.o.lines - 4, "popup exceeds a small editor")
key(buf, "q")
dashboard.collect, project.external_validate_async = collect, validate
vim.o.columns, vim.o.lines, vim.o.scrolloff = columns, lines, scrolloff
