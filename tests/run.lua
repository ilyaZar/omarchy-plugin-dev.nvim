local config = require("omarchy_plugin_dev.config")
local project = require("omarchy_plugin_dev.project")
local tasks = require("omarchy_plugin_dev.tasks")

local temp_root = vim.fn.tempname()
assert(vim.fn.mkdir(temp_root, "p") == 1, "temporary root was not created")

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines, path) == 0, "failed to write " .. path)
end

local function make_executable(path)
  assert(vim.fn.setfperm(path, "rwxr-xr-x") == 1, "failed to make executable " .. path)
end

local function create_project(root)
  write(vim.fs.joinpath(root, "Service.qml"), { "import QtQuick", "Item {}" })
  write(vim.fs.joinpath(root, "manifest.json"), {
    "{",
    '  "schemaVersion": 1,',
    '  "id": "dev.example",',
    '  "name": "Example",',
    '  "version": "1.0.0",',
    '  "kinds": ["service"],',
    '  "entryPoints": {"service": "Service.qml"}',
    "}",
  })
end

local function accept_validation()
  return true
end

local function mapping_by_desc(bufnr, desc)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if mapping.desc == desc then
      return mapping
    end
  end
end

for _, name in ipairs({
  "OmaDev",
  "OmaDevInit",
  "OmaDevTest",
  "OmaDevHotReload",
  "OmaDevRebuild",
  "OmaDevHealth",
}) do
  assert(vim.fn.exists(":" .. name) == 2, name .. " command is missing")
end
for _, name in ipairs({
  "OmaDevCheck",
  "OmaDevReload",
  "OmaDevCheckReload",
  "OmaDevTasks",
  "OmaDevLogs",
  "OmaDevDoctor",
  "OmarchyQmlDev",
  "OmarchyPluginDev",
}) do
  assert(vim.fn.exists(":" .. name) == 0, name .. " command remains registered")
end
for _, name in ipairs({
  "dashboard",
  "test",
  "hot_reload",
  "rebuild",
  "health",
  "edit_tasks",
  "init_project",
}) do
  assert(require("omarchy_plugin_dev")[name] == nil, name .. " remains in the top-level Lua API")
end

local root = vim.fs.joinpath(temp_root, "plugin with spaces")
create_project(root)
local test_runner = vim.fs.joinpath(root, "scripts", "test")
write(test_runner, { "#!/bin/bash", "exit 0" })
make_executable(test_runner)
local nested = vim.fs.joinpath(root, "nested")
vim.fn.mkdir(nested, "p")
local qml_path = vim.fs.joinpath(nested, "View.qml")
write(qml_path, { "import QtQuick", "Item {}" })

local detected = assert(project.detect(qml_path))
assert(detected.root == project.canonical(root), "project root detection used the wrong root")
assert(detected.manifest.id == "dev.example", "detected manifest changed")

local unrelated = vim.fs.joinpath(temp_root, "unrelated")
write(vim.fs.joinpath(unrelated, "View.qml"), { "Item {}" })
assert(project.detect(unrelated) == nil, "unrelated QML project was detected")

local package_root = vim.fs.joinpath(temp_root, "package")
write(vim.fs.joinpath(package_root, "manifest.json"), { '{"name":"not an Omarchy plugin"}' })
write(vim.fs.joinpath(package_root, "View.qml"), { "Item {}" })
assert(project.detect(package_root) == nil, "unrelated manifest was accepted")

local parsed = assert(
  project.decode_tasks(
    '{"version":1,"tasks":{"test":{"command":["./scripts/test","--unit"]}}}',
    "memory"
  )
)
assert(parsed.tasks.test.command[2] == "--unit", "task argv parsing changed")
assert(project.decode_tasks("{", "memory") == nil, "malformed JSON was accepted")
assert(
  project.decode_tasks('{"version":1,"tasks":{"test":{"command":"make test"}}}', "memory") == nil,
  "shell-string command was accepted"
)
assert(
  project.decode_tasks('{"version":2,"tasks":{}}', "memory") == nil,
  "unsupported tasks schema was accepted"
)
assert(
  project.decode_tasks('{"version":1,"tasks":{"reload":{"command":["custom-reload"]}}}', "memory"),
  "released custom task name was rejected"
)
assert(
  project.decode_tasks(
    '{"version":1,"tasks":{"check_reload":{"command":["custom-workflow"]}}}',
    "memory"
  ),
  "available custom task name was rejected"
)

local test_candidates = project.test_candidates(root)
assert(#test_candidates == 1, "conventional test runner was not detected exactly once")
assert(
  vim.deep_equal(test_candidates[1].command, { "./scripts/test" }),
  "detected test runner command changed"
)
assert(project.test_state(root).kind == "candidate", "unconfigured test runner state is wrong")

local initialized = assert(project.initialize(root, {
  test_command = test_candidates[1].command,
  validator = accept_validation,
}))
local gitignore_path = vim.fs.joinpath(root, ".gitignore")
assert(vim.fn.filereadable(gitignore_path) == 1, "initialization did not create .gitignore")
assert(
  vim.tbl_contains(vim.fn.readfile(gitignore_path), ".omarchy-plugin-dev/"),
  "project task directory was not ignored"
)
local initialized_data = assert(project.load_tasks(root))
assert(
  vim.deep_equal(initialized_data.tasks.test.command, { "./scripts/test" }),
  "initial test command changed"
)
write(initialized, { '{"version":1,"tasks":{"test":{"command":["custom-test"]}}}' })
local created_again, _, state = project.initialize(root, { validator = accept_validation })
assert(created_again == nil and state == "exists", "initialization overwrote without approval")
local preserved = assert(project.load_tasks(root))
assert(preserved.tasks.test.command[1] == "custom-test", "existing tasks.json was modified")
assert(
  project.initialize(root, {
    force = true,
    test_command = test_candidates[1].command,
    validator = accept_validation,
  }),
  "explicit overwrite failed"
)
local ignore_count = 0
for _, line in ipairs(vim.fn.readfile(gitignore_path)) do
  if line == ".omarchy-plugin-dev/" then
    ignore_count = ignore_count + 1
  end
end
assert(ignore_count == 1, "initialization duplicated the .gitignore entry")
assert(vim.fn.filereadable(vim.fs.joinpath(root, ".qmlls.ini")) == 0, "dead LSP config was created")
assert(project.test_state(root).kind == "configured", "configured test runner state is wrong")

local unaggregated_root = vim.fs.joinpath(temp_root, "plugin with unaggregated tests")
create_project(unaggregated_root)
write(vim.fs.joinpath(unaggregated_root, "tests", "test_service.sh"), { "#!/bin/bash" })
assert(
  project.test_state(unaggregated_root).kind == "unaggregated",
  "unaggregated tests were not distinguished from an aggregate runner"
)
assert(
  project.initialize(unaggregated_root, { validator = accept_validation }),
  "initialization without a test runner failed"
)
local unaggregated_data = assert(project.load_tasks(unaggregated_root))
assert(unaggregated_data.tasks.test == nil, "initialization invented a test command")

config.setup({ executables = { omarchy = "/bin/false" } })
local async_validation_done = false
local async_validation_result
local async_validation_error
project.external_validate_async(project.canonical(root), function(valid, validation_error)
  async_validation_result = valid
  async_validation_error = validation_error
  async_validation_done = true
end)
assert(
  vim.wait(3000, function()
    return async_validation_done
  end),
  "asynchronous official validation did not finish"
)
assert(async_validation_result == false, "failed official validation was reported as successful")
assert(async_validation_error == "validation failed", "official validation failure was unclear")
config.setup()

local fake_shell_root = vim.fs.joinpath(temp_root, "fake shell")
write(vim.fs.joinpath(fake_shell_root, "shell.qml"), { "import QtQuick", "Item {}" })
write(vim.fs.joinpath(fake_shell_root, "Commons", "qmldir"), { "module qs.Commons" })
local qml_cache_root = vim.fs.joinpath(temp_root, "qml cache")
config.setup({ qml_import_paths = { fake_shell_root } })
local qml_import_paths, qml_import_error = require("omarchy_plugin_dev.qml").import_paths({
  cache_root = qml_cache_root,
})
assert(qml_import_error == nil, "QML import bridge failed: " .. tostring(qml_import_error))
assert(#qml_import_paths == 2, "QML import bridge changed the resolved path count")
assert(
  vim.uv.fs_realpath(vim.fs.joinpath(qml_import_paths[1], "qs"))
    == project.canonical(fake_shell_root),
  "QML import bridge does not expose the Quickshell root as qs"
)
assert(
  qml_import_paths[2] == vim.fs.normalize(fake_shell_root),
  "configured QML import path was not preserved"
)
config.setup()

local check_spec = assert(tasks.check_spec(project.canonical(root)))
assert(check_spec.cwd == project.canonical(root), "check task cwd is wrong")
local validate_step = check_spec.strategy.tasks[1]
assert(
  vim.deep_equal(validate_step.cmd, {
    "omarchy",
    "plugin",
    "validate",
    project.canonical(root),
  }),
  "validation argv is wrong"
)
local lint_step = check_spec.strategy.tasks[2]
local lint_info = assert(require("omarchy_plugin_dev.qmllint").resolve())
assert(lint_info.major >= 6, "automatic qmllint resolution selected a pre-Qt-6 executable")
assert(lint_step.cmd[1] == lint_info.path, "lint task does not use the resolved Qt 6 qmllint")
assert(lint_step.cmd[2] == "-I", "lint task lost the import flag")
assert(
  vim.uv.fs_realpath(vim.fs.joinpath(lint_step.cmd[3], "qs"))
    == vim.uv.fs_realpath("/usr/share/omarchy/shell"),
  "lint task lost the qs namespace bridge"
)
assert(
  lint_step.cmd[4] == "-I" and lint_step.cmd[5] == "/usr/share/omarchy/shell",
  "lint task lost direct Omarchy imports"
)
assert(
  lint_step.components[1].set_diagnostics == false,
  "lint task still duplicates language-server diagnostics"
)
assert(lint_step.cwd == project.canonical(root), "lint task cwd is wrong")

local test_spec = assert(tasks.test_spec(project.canonical(root)))
assert(
  vim.deep_equal(test_spec.cmd, { vim.fs.joinpath(project.canonical(root), "scripts", "test") }),
  "relative test executable was not anchored to the project root"
)
assert(test_spec.cwd == project.canonical(root), "test task cwd is wrong")

local no_test_root = vim.fs.joinpath(temp_root, "plugin without tests")
create_project(no_test_root)
local missing_test_rebuild, missing_test_error = tasks.rebuild_spec(project.canonical(no_test_root))
assert(missing_test_rebuild == nil, "test-and-build accepted a missing test task")
assert(
  missing_test_error and missing_test_error:find("No test task is configured", 1, true),
  "test-and-build did not explain its missing test task"
)
config.setup({
  tasks = {
    rebuild = { cmd = { "/bin/true" }, name = "Custom rebuild" },
  },
})
local custom_rebuild = assert(tasks.rebuild_spec(project.canonical(no_test_root)))
assert(vim.deep_equal(custom_rebuild.cmd, { "/bin/true" }), "custom rebuild override was ignored")
config.setup({ tasks = { rebuild = { name = "Partial rebuild override" } } })
assert(
  tasks.rebuild_spec(project.canonical(no_test_root)) == nil,
  "partial rebuild override bypassed the required test"
)
local function_default
config.setup({
  tasks = {
    rebuild = function(context)
      function_default = context.default
      context.default.name = "Function rebuild"
      return context.default
    end,
  },
})
local function_rebuild = assert(tasks.rebuild_spec(project.canonical(root)))
assert(function_default ~= nil, "rebuild function override lost its default spec")
assert(function_rebuild.name == "Function rebuild", "rebuild function override was not applied")
config.setup()

local hot_reload_spec = assert(tasks.hot_reload_spec(project.canonical(root)))
local hot_reload_steps = hot_reload_spec.strategy.tasks
assert(#hot_reload_steps == 3, "build should check, deploy, and restart exactly once")
assert(
  hot_reload_steps[2].cmd[1]:match("/scripts/deploy$"),
  "build does not use the staged deployment helper"
)
assert(
  vim.deep_equal(hot_reload_steps[3].cmd, { "omarchy", "restart", "shell" }),
  "build does not expose the shell restart as an Overseer step"
)

local rebuild_spec = assert(tasks.rebuild_spec(project.canonical(root)))
local rebuild_steps = rebuild_spec.strategy.tasks
local restart_count = 0
for _, step in ipairs(rebuild_steps) do
  if step.cmd and vim.deep_equal(step.cmd, { "omarchy", "restart", "shell" }) then
    restart_count = restart_count + 1
  end
end
assert(restart_count == 1, "test-and-build must restart the shell exactly once")
assert(
  rebuild_steps[2].metadata.omarchy_plugin_dev_action == "test",
  "configured test was silently omitted from the rebuild"
)
assert(
  rebuild_steps[#rebuild_steps].metadata.omarchy_plugin_dev_action == "restart",
  "test-and-build does not end with the shell restart"
)

config.setup()
local lsp = require("omarchy_plugin_dev.lsp")
assert(lsp.executable(), "installed canonical qmlls was not discovered")
if vim.fn.executable("/usr/lib/qt6/bin/qmlls") == 1 then
  assert(
    lsp.executable() == "/usr/lib/qt6/bin/qmlls",
    "automatic QML server resolution did not prefer the system Qt server"
  )
end

local original_notify = vim.notify
local notifications = {}
rawset(vim, "notify", function(message, _level, _opts)
  notifications[#notifications + 1] = message
end)
config.setup({
  executables = {
    qml_language_server = "definitely-missing-qml-language-server",
    qmllint = "definitely-missing-qmllint",
  },
})
assert(tasks.check(project.canonical(root)) == nil, "check ran with a missing qmllint")
assert(#notifications == 1, "missing executable did not produce one actionable notification")
assert(notifications[1]:find("not executable", 1, true), "missing executable message is unclear")
rawset(vim, "notify", original_notify)
config.setup({
  executables = {
    jq = "/bin/true",
    omarchy = "/bin/true",
    qml_language_server = "definitely-missing-qml-language-server",
    qmllint = "/bin/true",
    rsync = "/bin/true",
  },
})

notifications = {}
rawset(vim, "notify", function(message, _level, _opts)
  notifications[#notifications + 1] = message
end)
local unavailable_test_root = vim.fs.joinpath(temp_root, "plugin with unavailable test")
create_project(unavailable_test_root)
assert(project.initialize(unavailable_test_root, {
  test_command = { "./scripts/missing-test" },
  validator = accept_validation,
}))
assert(
  tasks.rebuild(project.canonical(unavailable_test_root)) == nil,
  "rebuild silently skipped an unavailable test"
)
assert(
  #notifications == 1 and notifications[1]:find("Test is unavailable", 1, true),
  "rebuild did not explain the unavailable configured test"
)
rawset(vim, "notify", original_notify)
config.setup()

local project_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(project_buf)
vim.api.nvim_buf_set_name(project_buf, qml_path)
require("omarchy_plugin_dev.mappings").detach(project_buf)
vim.keymap.set("n", "<localleader>b", "<cmd>let g:user_mapping_ran = 1<cr>", {
  buffer = project_buf,
  desc = "User conflict",
})
vim.bo[project_buf].filetype = "qml"
require("omarchy_plugin_dev").attach(project_buf)
assert(mapping_by_desc(project_buf, "User conflict"), "existing mapping was overwritten")
assert(
  not mapping_by_desc(project_buf, "Omarchy Plugin: check"),
  "removed check mapping was installed"
)
assert(
  not mapping_by_desc(project_buf, "Omarchy Plugin: reload or restart shell"),
  "removed reload mapping was installed"
)
assert(
  mapping_by_desc(project_buf, "Omarchy Plugin: test"),
  "project-local test mapping is missing"
)
assert(
  mapping_by_desc(project_buf, "Omarchy Plugin: build and restart"),
  "Ctrl+B mapping is missing"
)
assert(
  mapping_by_desc(project_buf, "Omarchy Plugin: test, build, and restart"),
  "Ctrl+Shift+B mapping is missing"
)
local lsp_root
require("omarchy_plugin_dev.lsp").root_dir(project_buf, function(root_dir)
  lsp_root = root_dir
end)
assert(lsp_root == project.canonical(root), "LSP root did not use the detected Omarchy project")

local original_get_clients = vim.lsp.get_clients
local original_detach_client = vim.lsp.buf_detach_client
local original_diagnostic_reset = vim.diagnostic.reset
local original_get_namespace = vim.lsp.diagnostic.get_namespace
local detached_clients = {}
local reset_namespaces = {}
vim.lsp.get_clients = function(opts)
  assert(opts.bufnr == project_buf, "LSP ownership queried the wrong buffer")
  return {
    { id = 17, name = "qmlls", namespace = 71 },
    { id = 18, name = "omarchy_plugin_dev", namespace = 72 },
  }
end
vim.lsp.buf_detach_client = function(bufnr, client_id)
  assert(bufnr == project_buf, "generic QML server was detached from the wrong buffer")
  detached_clients[#detached_clients + 1] = client_id
end
vim.lsp.diagnostic.get_namespace = function(client_id)
  return client_id + 54
end
vim.diagnostic.reset = function(namespace, bufnr)
  assert(bufnr == project_buf, "generic diagnostics were reset for the wrong buffer")
  reset_namespaces[#reset_namespaces + 1] = namespace
end
assert(lsp.claim(project_buf), "detected project buffer did not claim QML server ownership")
assert(vim.deep_equal(detached_clients, { 17 }), "project detached the wrong QML client")
assert(vim.deep_equal(reset_namespaces, { 71 }), "generic QML diagnostics were not cleared")
config.setup({
  executables = { qml_language_server = "definitely-missing-qml-language-server" },
})
detached_clients = {}
assert(not lsp.claim(project_buf), "missing project-aware server still claimed the buffer")
assert(#detached_clients == 0, "generic QML server was detached without a replacement")
config.setup()
vim.lsp.get_clients = original_get_clients
vim.lsp.buf_detach_client = original_detach_client
vim.lsp.diagnostic.get_namespace = original_get_namespace
vim.diagnostic.reset = original_diagnostic_reset

for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
  assert(
    not mapping.desc or not mapping.desc:find("Omarchy Plugin:", 1, true),
    "mapping leaked globally"
  )
end

vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(unrelated, "View.qml")))
vim.bo.filetype = "qml"
local unrelated_buf = vim.api.nvim_get_current_buf()
require("omarchy_plugin_dev").attach(unrelated_buf)
assert(
  not mapping_by_desc(unrelated_buf, "Omarchy Plugin: test"),
  "unrelated QML buffer received project mappings"
)
local unrelated_lsp_root
require("omarchy_plugin_dev.lsp").root_dir(unrelated_buf, function(root_dir)
  unrelated_lsp_root = root_dir
end)
assert(unrelated_lsp_root == nil, "LSP root callback claimed an unrelated QML project")

local created_tasks = {}
local opened = {}
local original_overseer = package.loaded.overseer
package.loaded.overseer = {
  new_task = function(spec)
    local task = { id = #created_tasks + 1, metadata = spec.metadata, spec = spec, starts = 0 }
    function task:start()
      self.starts = self.starts + 1
    end
    created_tasks[#created_tasks + 1] = task
    return task
  end,
  open = function(opts)
    opened[#opened + 1] = opts
  end,
  list_tasks = function()
    return created_tasks
  end,
}
config.setup({
  executables = { qml_language_server = "definitely-missing-qml-language-server" },
})
local check_task = assert(tasks.check(project.canonical(root)))
assert(check_task.starts == 1, "check task did not start")
assert(check_task.spec.cwd == project.canonical(root), "visible check task has the wrong root")
assert(opened[#opened].focus_task_id == check_task.id, "check task was not shown in Overseer")

vim.cmd.buffer(project_buf)
vim.cmd.OmaDev()
assert(vim.bo.filetype == "omarchy-plugin-dev", "dashboard did not open")
local dashboard_buf = vim.api.nvim_get_current_buf()
local dashboard_lines = vim.api.nvim_buf_get_lines(dashboard_buf, 0, -1, false)
assert(
  dashboard_lines[3]:find("manifest: recognized", 1, true),
  "dashboard overstates lightweight manifest recognition"
)
assert(
  vim.wait(5000, function()
    local line = vim.api.nvim_buf_get_lines(dashboard_buf, 3, 4, false)[1] or ""
    return line:find("official validation: passed", 1, true) ~= nil
  end),
  "dashboard did not report official Omarchy validation"
)
dashboard_lines = vim.api.nvim_buf_get_lines(dashboard_buf, 0, -1, false)
assert(
  table.concat(dashboard_lines, "\n"):find(lint_info.path, 1, true),
  "dashboard does not show the resolved qmllint path"
)
assert(
  table.concat(dashboard_lines, "\n"):find("test task: configured", 1, true),
  "dashboard does not show the configured test state"
)
vim.cmd.close()
vim.cmd.buffer(project_buf)
vim.cmd.OmaDevHealth()
assert(vim.bo.filetype == "checkhealth", "health report did not open")
vim.cmd.close()

package.loaded.overseer = original_overseer
assert(vim.fn.delete(temp_root, "rf") == 0, "temporary test tree was not removed")

print("omarchy-plugin-dev.nvim tests passed")
