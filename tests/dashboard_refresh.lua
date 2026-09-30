---@diagnostic disable: duplicate-set-field
local config = require("omarchy-plugin-dev.config")
local project = require("omarchy-plugin-dev.project")
local actions = require("omarchy-plugin-dev.actions")
local lsp = require("omarchy-plugin-dev.lsp")
local messages = require("omarchy-plugin-dev.messages")
local saved_config = vim.deepcopy(config.get())
local saved_validate, saved_lsp, saved_show =
  project.external_validate_async, lsp.status, messages.show
local saved_overseer, saved_preload = package.loaded.overseer, package.preload.overseer
local main_win, main_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
local columns, lines = vim.o.columns, vim.o.lines
vim.o.columns, vim.o.lines = 120, 40
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/bin", "p")
assert(vim.system({ "git", "-C", root, "init", "-q" }):wait().code == 0)
local source_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(source_buf, root .. "/Service.qml")
vim.fn.writefile({ "import QtQuick", "Item {}" }, root .. "/Service.qml")
local manifest = { schemaVersion = 1, id = "dev.refresh" }
local function save_manifest()
  vim.fn.writefile({ vim.json.encode(manifest) }, root .. "/manifest.json")
end
save_manifest()
local tool, lint = root .. "/bin/tool", root .. "/bin/qmllint"
local function executable(path, body)
  vim.fn.writefile({ "#!/bin/sh", body }, path)
  assert(vim.fn.setfperm(path, "rwx------") == 1)
end
executable(tool, 'touch "$0.executed"')
local function lint_version(version)
  executable(lint, "printf 'qmllint " .. version .. "\\n'; printf 'probe\\n' >> \"$0.probes\"")
end
lint_version("6.10.0")
local options = {
  executables = { omarchy = tool, qmllint = lint, jq = tool, rsync = tool, journalctl = tool },
  logs = { match = "first logs" },
  mappings = { hot_reload = "<F5>", build = "<F6>" },
}
config.setup(options)
local pending, notices = {}, {}
project.external_validate_async = function(path, callback)
  assert(path == root, "refresh validated a different project")
  pending[#pending + 1] = callback
end
local lsp_state, lsp_detail = "available", "not started"
lsp.status = function(bufnr)
  assert(bufnr == source_buf, "refresh used the dashboard or current buffer for LSP status")
  return lsp_state, lsp_detail
end
messages.show = function(message)
  notices[#notices + 1] = message
end
package.loaded.overseer = {}
local function key(buf, lhs)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if mapping.lhs == lhs then
      mapping.callback()
      return
    end
  end
  error("missing dashboard key: " .. lhs)
end
local function text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
local namespace = vim.api.nvim_get_namespaces()["omarchy-plugin-dev.dashboard"]
local function field(buf, label, value, group)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if vim.startswith(line, "  " .. label .. ":") then
      assert(line:find(value, 1, true), label .. " did not refresh: " .. line)
      if group then
        local marks = vim.api.nvim_buf_get_extmarks(
          buf,
          namespace,
          { index - 1, 0 },
          { index - 1, -1 },
          {
            details = true,
          }
        )
        assert(marks[2][4].hl_group == group, label .. " has the wrong theme highlight")
      end
      return
    end
  end
  error("missing dashboard field: " .. label)
end

vim.api.nvim_set_current_buf(source_buf)
local buf, win = actions.dashboard(0)
assert(buf and win)
assert(text(buf):find("[1] Build  [2] Status  [3] Settings", 1, true))
assert(text(buf):find("  Actions ", 1, true), "Build is not the initial tab")
key(buf, "2")
field(buf, "test task", "tests NOT detected", "DiagnosticError")
field(buf, "official validation", "checking")
field(buf, "manifest", "dev.refresh")
field(buf, "qmllint", "6.10.0", "DiagnosticOk")
field(buf, "Overseer", "available")
field(buf, "project tasks", "not initialized")
assert(
  #pending == 1 and #vim.fn.readfile(lint .. ".probes") == 1,
  "initial collection ran more than once"
)
for _, tab in ipairs({ "1", "3", "2" }) do
  key(buf, tab)
end
assert(
  #pending == 1 and #vim.fn.readfile(lint .. ".probes") == 1,
  "tab navigation recollected state"
)

vim.fn.mkdir(root .. "/tests", "p")
vim.fn.writefile({ "test fixture" }, root .. "/tests/example.lua")
field(buf, "test task", "tests NOT detected")
manifest.id, manifest.schemaVersion = "dev.refreshed", 42
save_manifest()
lint_version("6.11.1")
lsp_state, lsp_detail = "running", "running as client 17"
vim.fn.mkdir(root .. "/.omarchy-plugin-dev", "p")
vim.fn.writefile(
  { vim.json.encode({ version = 1, tasks = { audit = { command = { tool } } } }) },
  project.tasks_path(root)
)
assert(vim.fn.delete(tool) == 0)
options.logs.match = "refreshed logs"
options.config_file = "lua/refreshed-settings.lua"
options.mappings = { hot_reload = "<C-b>", build = "<C-S-b>" }
config.setup(options)
package.loaded.overseer = nil
package.preload.overseer = function()
  error("Overseer unavailable in refresh fixture")
end
key(buf, "3")
key(buf, "G")
local cursor = vim.api.nvim_win_get_cursor(win)
-- The original source stays authoritative even if another window has focus.
vim.api.nvim_set_current_win(main_win)
local other_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(other_buf)
key(buf, "r")
assert(vim.api.nvim_get_current_win() == main_win, "refresh stole focus")
assert(vim.deep_equal(cursor, vim.api.nvim_win_get_cursor(win)), "refresh moved selection")
assert(text(buf):find("Build keybindings", 1, true), "refresh changed tabs")
field(buf, "hot reload", "Ctrl+b")
field(buf, "build", "Ctrl+Shift+b")
assert(text(buf):find("Enter: edit keybindings", 1, true), "settings hints did not refresh")
assert(#pending == 2 and #vim.fn.readfile(lint .. ".probes") == 2, "refresh did not recollect once")
key(buf, "1")
assert(text(buf):find("Open refreshed-settings.lua", 1, true), "action details did not refresh")
pending[1](false, "stale validation")
key(buf, "2")
field(buf, "official validation", "checking")
assert(not text(buf):find("stale validation", 1, true), "old validation overwrote refreshed state")
field(buf, "test task", "tests found, no aggregate runner", "DiagnosticWarn")
field(buf, "manifest", "dev.refreshed", "DiagnosticError")
field(buf, "manifest", "schema v42")
field(buf, "project tasks", "valid", "DiagnosticOk")
field(buf, "qml-language-server", "running as client 17", "DiagnosticOk")
field(buf, "qmllint", "6.11.1", "DiagnosticOk")
field(buf, "Overseer", "missing", "DiagnosticError")
for _, name in ipairs({ "omarchy", "jq", "rsync", "logs" }) do
  field(buf, name, "missing", "DiagnosticError")
end
field(buf, "logs", "refreshed logs")
pending[2](false, "fresh validation\nnew detail")
field(buf, "official validation", "fresh validation | new detail", "DiagnosticError")

key(buf, "r")
key(buf, "r")
pending[3](false, "out of order")
field(buf, "official validation", "checking")
pending[4](true)
field(buf, "official validation", "passed", "DiagnosticOk")
assert(not text(buf):find("out of order", 1, true), "rapid refresh accepted stale validation")
assert(vim.uv.fs_rename(root .. "/tests", root .. "/held"))
key(buf, "r")
field(buf, "test task", "tests NOT detected", "DiagnosticError")
assert(vim.uv.fs_rename(root .. "/held", root .. "/tests"))
key(buf, "r")
field(buf, "test task", "tests found, no aggregate runner", "DiagnosticWarn")

executable(tool, 'touch "$0.executed"')
vim.fn.writefile(
  { vim.json.encode({ version = 1, tasks = { test = { command = { tool } } } }) },
  project.tasks_path(root)
)
key(buf, "r")
field(buf, "test task", "configured", "DiagnosticOk")
assert(vim.fn.filereadable(tool .. ".executed") == 0, "refresh executed a configured test")
assert(vim.fn.delete(tool) == 0)
key(buf, "r")
field(buf, "test task", "configured, executable missing", "DiagnosticError")
vim.fn.writefile({ "not JSON" }, project.tasks_path(root))
key(buf, "r")
field(buf, "project tasks", "invalid", "DiagnosticError")
field(buf, "test task", "invalid", "DiagnosticError")

local theme_groups = {
  Normal = true,
  Comment = true,
  DiagnosticOk = true,
  DiagnosticWarn = true,
  DiagnosticError = true,
  DiagnosticInfo = true,
  Bold = true,
}
for _, tab in ipairs({ "1", "2", "3" }) do
  key(buf, tab)
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })) do
    local groups = mark[4].hl_group
    for _, group in ipairs(type(groups) == "table" and groups or { groups }) do
      assert(
        theme_groups[group],
        "dashboard does not use a standard theme highlight: " .. tostring(group)
      )
    end
  end
end

local late = pending[#pending]
vim.fn.writefile({ "not JSON" }, root .. "/manifest.json")
key(buf, "r")
assert(not vim.api.nvim_win_is_valid(win), "failed refresh retained stale dashboard information")
assert(notices[#notices]:find("Cannot refresh dashboard:", 1, true))
assert(notices[#notices]:find("not valid JSON", 1, true))
late(false, "closed dashboard result")
save_manifest()
local retained_buf, retained_win = actions.dashboard(source_buf)
assert(retained_buf and retained_win)
vim.bo[retained_buf].bufhidden = "hide"
vim.api.nvim_win_close(retained_win, true)
assert(vim.api.nvim_buf_is_valid(retained_buf))
pending[#pending](false, "hidden dashboard result")
vim.api.nvim_buf_delete(retained_buf, { force = true })
local new_buf, new_win = actions.dashboard(source_buf)
assert(new_buf and new_win, "dashboard could not reopen after manifest repair")
late(false, "old dashboard result")
assert(not text(new_buf):find("old dashboard result", 1, true))
vim.api.nvim_buf_delete(source_buf, { force = true })
key(new_buf, "r")
assert(not vim.api.nvim_win_is_valid(new_win), "refresh did not reject a deleted source buffer")
assert(notices[#notices]:find("buffer has no usable path", 1, true))
pending[#pending](true)

project.external_validate_async, lsp.status, messages.show = saved_validate, saved_lsp, saved_show
package.loaded.overseer, package.preload.overseer = saved_overseer, saved_preload
vim.api.nvim_set_current_win(main_win)
vim.api.nvim_set_current_buf(main_buf)
vim.api.nvim_buf_delete(other_buf, { force = true })
vim.o.columns, vim.o.lines = columns, lines
---@diagnostic disable-next-line: param-type-mismatch
config.setup(saved_config)
assert(vim.fn.delete(root, "rf") == 0)
