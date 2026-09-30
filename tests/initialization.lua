---@diagnostic disable: duplicate-set-field
local actions = require("omarchy-plugin-dev.actions")
local messages = require("omarchy-plugin-dev.messages")
local project = require("omarchy-plugin-dev.project")
local saved_async = project.external_validate_async
local saved_select = vim.ui.select
local saved_show = messages.show
local original_buf = vim.api.nvim_get_current_buf()
local root = vim.fn.tempname()
local pending, notices, buffers = {}, {}, {}

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines, path) == 0)
end

local function fixture(name, runner)
  local path = vim.fs.joinpath(root, name)
  write(vim.fs.joinpath(path, "Service.qml"), { "import QtQuick", "Item {}" })
  write(vim.fs.joinpath(path, "manifest.json"), {
    vim.json.encode({
      schemaVersion = 1,
      id = "dev." .. name,
      name = name,
      version = "1.0.0",
      kinds = { "service" },
      entryPoints = { service = "Service.qml" },
    }),
  })
  if runner then
    local script = vim.fs.joinpath(path, "scripts", "test")
    write(script, { "#!/bin/sh", "exit 0" })
    vim.fn.setfperm(script, "rwxr-xr-x")
  end
  local buf = vim.fn.bufadd(vim.fs.joinpath(path, "Service.qml"))
  vim.fn.bufload(buf)
  buffers[#buffers + 1] = buf
  return path, buf
end

project.external_validate_async = function(path, callback)
  pending[#pending + 1] = { path = path, callback = callback }
end
messages.show = function(message)
  notices[#notices + 1] = message
end

local selected, choices
vim.ui.select = function(items, _, callback)
  choices, selected = items, callback
end

local a, a_buf = fixture("a", true)
vim.api.nvim_set_current_buf(a_buf)
actions.init_project(0)
assert(selected and #pending == 0, "runner selection did not precede validation")
for _, choice in ipairs(choices) do
  if choice.command then
    selected(choice)
    break
  end
end
assert(
  #pending == 1 and pending[1].path == project.canonical(a),
  "validation lost its project root"
)
assert(vim.fn.filereadable(project.tasks_path(a)) == 0, "initialization wrote before validation")
local b, b_buf = fixture("b")
vim.api.nvim_set_current_buf(b_buf)
pending[1].callback(true)
assert(vim.fn.filereadable(project.tasks_path(a)) == 1, "delayed validation did not create tasks")
assert(
  project.load_tasks(a).builds[1].tasks.test.command[1] == "./scripts/test",
  "runner choice was lost"
)
assert(vim.api.nvim_get_current_buf() == b_buf, "completion changed the active buffer")

actions.init_project(b_buf)
assert(#pending == 2, "validation did not start for the new project")
pending[2].callback(false, "rejected by Omarchy")
assert(vim.fn.filereadable(project.tasks_path(b)) == 0, "failed validation wrote tasks")
assert(notices[#notices]:find("rejected by Omarchy", 1, true), "failure was not readable")

actions.init_project(b_buf)
actions.init_project(b_buf)
assert(#pending == 4, "repeated requests did not start")
pending[3].callback(true)
assert(vim.fn.filereadable(project.tasks_path(b)) == 0, "stale request wrote tasks")
pending[4].callback(true)
assert(vim.fn.filereadable(project.tasks_path(b)) == 1, "latest request did not create tasks")

local c, c_buf = fixture("c")
vim.api.nvim_set_current_buf(c_buf)
actions.init_project(c_buf)
local concurrent = project.tasks_path(c)
write(concurrent, { '{"version":1,"tasks":{}}' })
pending[5].callback(true)
assert(
  vim.fn.readfile(concurrent)[1] == '{"version":1,"tasks":{}}',
  "concurrent file was overwritten"
)
assert(notices[#notices]:find("already exists", 1, true), "concurrent file error was unclear")

local d, d_buf = fixture("d")
local approved = project.tasks_path(d)
write(approved, { '{"version":1,"tasks":{}}' })
vim.api.nvim_set_current_buf(d_buf)
actions.init_project(d_buf, { force = true })
write(approved, { '{"version":1,"tasks":{"new":{"command":["true"]}}}' })
pending[6].callback(true)
assert(vim.fn.readfile(approved)[1]:find('"new"', 1, true), "changed approved file was overwritten")
assert(
  notices[#notices]:find("changed during validation", 1, true),
  "changed file error was unclear"
)

actions.init_project(d_buf)
selected(choices[1])
assert(#pending == 6, "keep existing started validation")
actions.init_project(d_buf)
selected(choices[2])
assert(#pending == 7, "approved overwrite did not start validation")
pending[7].callback(true)
assert(project.load_tasks(d).builds[1].tasks.new == nil, "approved overwrite was not applied")

local e, e_buf = fixture("e", true)
vim.api.nvim_set_current_buf(e_buf)
actions.init_project(e_buf)
selected(nil)
assert(#pending == 7, "cancelled runner choice started validation")
assert(vim.fn.filereadable(project.tasks_path(e)) == 0, "cancelled choice wrote tasks")

local f, f_buf = fixture("f")
vim.api.nvim_set_current_buf(f_buf)
vim.cmd.vsplit()
local source_win = vim.api.nvim_get_current_win()
actions.init_project(f_buf)
vim.api.nvim_win_close(source_win, true)
pending[8].callback(true)
assert(vim.fn.filereadable(project.tasks_path(f)) == 1, "closed source window cancelled creation")

project.external_validate_async = saved_async
local saved_system = vim.system
rawset(vim, "system", function(command, opts, callback)
  if type(command) ~= "table" or command[2] ~= "plugin" then
    return saved_system(command, opts, callback)
  end
  assert(opts.timeout == 10000, "official validator lost its timeout")
  callback({ code = 124, signal = 15, stdout = "", stderr = "" })
  return {}
end)
local timeout_detail
project.external_validate_async(a, function(valid, detail)
  assert(valid == false, "timed-out validation succeeded")
  timeout_detail = detail
end)
assert(
  vim.wait(1000, function()
    return timeout_detail ~= nil
  end),
  "timed-out validation did not complete"
)
assert(timeout_detail:find("timed out", 1, true), "timeout error was not readable")
rawset(vim, "system", saved_system)
vim.ui.select = saved_select
messages.show = saved_show
vim.api.nvim_set_current_buf(original_buf)
for _, buf in ipairs(buffers) do
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end
assert(vim.fn.delete(root, "rf") == 0, "initialization fixtures were not removed")
