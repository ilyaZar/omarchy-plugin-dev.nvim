local config = require("omarchy_plugin_dev.config")
local project = require("omarchy_plugin_dev.project")
local reload = require("omarchy_plugin_dev.reload")
local tasks = require("omarchy_plugin_dev.tasks")

local temp_root = vim.fn.tempname()
assert(vim.fn.mkdir(temp_root, "p") == 1, "temporary root was not created")

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines, path) == 0, "failed to write " .. path)
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
  project.decode_tasks('{"version":1,"tasks":{"reload":{"command":["unsafe-override"]}}}', "memory")
    == nil,
  "reserved built-in task name was accepted"
)

local initialized = assert(project.initialize(root, { validator = accept_validation }))
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
  project.initialize(root, { force = true, validator = accept_validation }),
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
assert(lint_step.cmd[1] == "qmllint", "lint task does not use qmllint")
assert(lint_step.cmd[2] == "-I", "lint task lost the import flag")
assert(lint_step.cmd[3] == "/usr/share/omarchy/shell", "lint task lost Omarchy imports")
assert(lint_step.cwd == project.canonical(root), "lint task cwd is wrong")

local test_spec = assert(tasks.test_spec(project.canonical(root)))
assert(vim.deep_equal(test_spec.cmd, { "./scripts/test" }), "test task argv changed")
assert(test_spec.cwd == project.canonical(root), "test task cwd is wrong")

local ipc_with_soft_reload = table.concat({
  "target shell",
  "  function ping(): string",
  "  function rescanPlugins(): void",
  "target other",
  "  function rescanPlugins(): void",
}, "\n")
assert(
  reload.parse_ipc_show(ipc_with_soft_reload, { target = "shell", method = "rescanPlugins" }),
  "verified soft reload endpoint was not detected"
)
assert(not reload.parse_ipc_show("target other\n  function rescanPlugins(): void", {
  target = "shell",
  method = "rescanPlugins",
}), "endpoint on the wrong target was accepted")
local restart_capability =
  reload.capability({ ipc_output = "target shell\n  function ping(): string" })
assert(restart_capability.kind == "restart", "missing soft reload did not fall back")
assert(
  vim.deep_equal(restart_capability.command, { "omarchy", "restart", "shell" }),
  "restart fallback argv is wrong"
)
local soft_capability = reload.capability({ ipc_output = ipc_with_soft_reload })
assert(soft_capability.kind == "soft", "verified soft reload was not selected")
assert(
  vim.deep_equal(soft_capability.command, { "omarchy-shell", "shell", "rescanPlugins" }),
  "soft reload argv is wrong"
)
local stale_ipc_capability = reload.capability({
  ipc_output = ipc_with_soft_reload,
  generation_reload = false,
})
assert(stale_ipc_capability.kind == "restart", "stale IPC rescan did not fall back to restart")
local soft_only_config = config.defaults()
soft_only_config.restart.mode = "soft"
local unavailable_soft_reload = reload.capability({
  config = soft_only_config,
  ipc_output = "target shell\n  function ping(): string",
})
assert(not unavailable_soft_reload.available, "soft-only mode silently fell back to restart")

local hot_reload_spec = assert(tasks.hot_reload_spec(project.canonical(root)))
local hot_reload_steps = hot_reload_spec.strategy.tasks
assert(#hot_reload_steps == 3, "hot reload should check, deploy, and reload exactly once")
assert(
  hot_reload_steps[2].cmd[1]:match("/scripts/deploy$"),
  "hot reload does not use the staged deployment helper"
)
assert(
  hot_reload_steps[3].cmd[1]:match("/scripts/hot%-reload$"),
  "hot reload does not use the runtime compatibility helper"
)

local rebuild_spec = assert(tasks.rebuild_spec(project.canonical(root)))
local rebuild_steps = rebuild_spec.strategy.tasks
local restart_count = 0
for _, step in ipairs(rebuild_steps) do
  if step.cmd and vim.deep_equal(step.cmd, { "omarchy", "restart", "shell" }) then
    restart_count = restart_count + 1
  end
end
assert(restart_count == 1, "clean rebuild must restart the shell exactly once")
assert(
  rebuild_steps[#rebuild_steps].metadata.omarchy_plugin_dev_action == "restart",
  "clean rebuild does not end with the shell restart"
)

config.setup()
local lsp = require("omarchy_plugin_dev.lsp")
assert(lsp.executable(), "installed canonical qmlls was not discovered")

local original_notify = vim.notify
local notifications = {}
vim.notify = function(message, _level, _opts)
  notifications[#notifications + 1] = message
end
config.setup({
  executables = {
    qml_language_server = "definitely-missing-qml-language-server",
    qmllint = "definitely-missing-qmllint",
  },
})
assert(tasks.check(project.canonical(root)) == nil, "check ran with a missing qmllint")
assert(#notifications == 1, "missing executable did not produce one actionable notification")
assert(notifications[1]:find("not executable", 1, true), "missing executable message is unclear")
vim.notify = original_notify
config.setup({
  executables = { qml_language_server = "definitely-missing-qml-language-server" },
})

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
assert(mapping_by_desc(project_buf, "Omarchy Plugin: hot reload"), "Ctrl+B mapping is missing")
assert(
  mapping_by_desc(project_buf, "Omarchy Plugin: clean rebuild"),
  "Ctrl+Shift+B mapping is missing"
)
local lsp_root
require("omarchy_plugin_dev.lsp").root_dir(project_buf, function(root_dir)
  lsp_root = root_dir
end)
assert(lsp_root == project.canonical(root), "LSP root did not use the detected Omarchy project")
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
vim.cmd.close()
vim.cmd.buffer(project_buf)
vim.cmd.OmaDevHealth()
assert(vim.bo.filetype == "checkhealth", "health report did not open")
vim.cmd.close()

package.loaded.overseer = original_overseer
assert(vim.fn.delete(temp_root, "rf") == 0, "temporary test tree was not removed")

print("omarchy-plugin-dev.nvim tests passed")
