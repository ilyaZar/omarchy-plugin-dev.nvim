local project = require("omarchy-plugin-dev.project")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local definitions = {}
local function state()
  return project.test_state(root, definitions)
end
local function write(relative, lines)
  local path = vim.fs.joinpath(root, relative)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines or { "test fixture" }, path) == 0)
  return path
end
local function git(...)
  local command = { "git", "-C", root }
  vim.list_extend(command, { ... })
  local result = vim.system(command, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end

git("init", "--quiet")
git("config", "core.excludesfile", "/dev/null")
write(".gitignore", { "/TODO/", "/ignored/" })
write("TODO/external/reference/tests/example.lua")
write("native/build/test_native")
assert(state().kind == "absent", "ignored reference tests counted as project tests")
assert(state().label:find("NOT detected", 1, true), "absent test label does not emphasize NOT")
for _, directory in ipairs({ "test", "tests", "spec", "specs" }) do
  local relative = "nested/" .. directory .. "/example.lua"
  local path = write(relative)
  assert(state().kind == "unaggregated", "nonignored tests were missed")
  git("add", relative)
  assert(state().kind == "unaggregated", "tracked tests were missed")
  assert(vim.fn.delete(path) == 0)
  assert(state().kind == "absent", "deleted tracked tests were still detected")
end
local tracked_ignored = write("ignored/tests/owned.lua")
git("add", "--force", "ignored/tests/owned.lua")
assert(state().kind == "unaggregated", "ignore rules hid tracked test sources")
assert(vim.fn.delete(tracked_ignored) == 0)
assert(state().kind == "absent")
local runner = write("scripts/test", { "#!/bin/sh", "exit 0" })
assert(vim.fn.setfperm(runner, "rwx------") == 1)
assert(state().kind == "candidate", "conventional runner detection changed")
definitions.test = { command = { "./scripts/test" } }
assert(state().kind == "configured", "configured test detection changed")
assert(vim.fn.delete(runner) == 0)
assert(state().kind == "unavailable", "missing configured test was hidden")
definitions.test = false
assert(state().kind == "disabled", "explicitly disabled tests were detected")
assert(vim.fn.delete(root, "rf") == 0)
