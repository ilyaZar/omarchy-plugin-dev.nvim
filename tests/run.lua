local config = require("omarchy-plugin-dev.config")
local project = require("omarchy-plugin-dev.project")
local task_specs = require("omarchy-plugin-dev.task_specs")
local tasks = require("omarchy-plugin-dev.tasks")

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
  "OmaDevBuild",
  "OmaDevHealth",
}) do
  assert(vim.fn.exists(":" .. name) == 2, name .. " command is missing")
end
for _, name in ipairs({
  "OmaDevCheck",
  "OmaDevRebuild",
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
  "build",
  "health",
  "edit_tasks",
  "init_project",
}) do
  assert(require("omarchy-plugin-dev")[name] == nil, name .. " remains in the top-level Lua API")
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
local excluded_qml_path = vim.fs.joinpath(root, "optional target", "View.qml")
write(excluded_qml_path, { "import QtQuick", "Item {}" })
local qml_js_path = vim.fs.joinpath(nested, "PanelModel.js")
write(qml_js_path, { ".pragma library", "function value() { return 1 }" })
local regular_js_path = vim.fs.joinpath(nested, "browser.js")
write(regular_js_path, { "export const value = 1" })
local ignored_qml_path = vim.fs.joinpath(root, "ignored", "Evidence.qml")
write(ignored_qml_path, { "import QtQuick", "Item {}" })
write(vim.fs.joinpath(root, ".gitignore"), { "/ignored/" })
local git_init = vim.system({ "git", "-C", root, "init", "--quiet" }, { text = true }):wait()
assert(git_init.code == 0, "temporary Git project was not initialized: " .. (git_init.stderr or ""))

local filetype = require("omarchy-plugin-dev.filetype")
assert(
  vim.treesitter.language.get_lang("qmljs") == "javascript",
  "QML JavaScript was not mapped to the JavaScript parser"
)
assert(filetype.detect(qml_js_path) == "qmljs", "QML JavaScript was not detected")
assert(filetype.detect(regular_js_path) == nil, "ordinary JavaScript was claimed")
local qml_js_buf = vim.fn.bufadd(qml_js_path)
vim.fn.bufload(qml_js_buf)
assert(
  vim.filetype.match({ filename = qml_js_path, buf = qml_js_buf }) == "qmljs",
  "registered QML JavaScript filetype did not match"
)
vim.api.nvim_buf_delete(qml_js_buf, { force = true })

local detected = assert(project.detect(qml_path))
assert(detected.root == project.canonical(root), "project root detection used the wrong root")
assert(detected.manifest.id == "dev.example", "detected manifest changed")
assert(project.detect_file(excluded_qml_path), "default ownership rejected a project QML file")

local filter_context
config.setup({
  qml_file_filter = function(context)
    filter_context = context
    return context.path ~= project.canonical(excluded_qml_path)
  end,
})
assert(project.detect_file(qml_path), "ownership filter rejected an included QML file")
assert(project.detect_file(excluded_qml_path) == nil, "ownership filter accepted excluded QML")
assert(filter_context.root == project.canonical(root), "ownership filter received the wrong root")
assert(filter_context.manifest.id == "dev.example", "ownership filter lost the manifest")
assert(
  filter_context.relative_path == "optional target/View.qml",
  "ownership filter received the wrong relative path"
)
assert(
  filter_context.path == project.canonical(excluded_qml_path),
  "ownership path is not canonical"
)
config.setup()

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
assert(
  initialized == vim.fs.joinpath(root, ".omarchy-plugin-dev", "task-config.json"),
  "initialization used the generic tasks.json name"
)
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
assert(preserved.tasks.test.command[1] == "custom-test", "existing task configuration was modified")
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

local legacy_root = vim.fs.joinpath(temp_root, "plugin with legacy task config")
create_project(legacy_root)
local legacy_path = vim.fs.joinpath(legacy_root, ".omarchy-plugin-dev", "tasks.json")
write(legacy_path, { '{"version":1,"tasks":{"test":{"command":["legacy-test"]}}}' })
assert(
  project.existing_tasks_path(legacy_root) == legacy_path,
  "legacy task configuration was not discovered"
)
local legacy_data = assert(project.load_tasks(legacy_root))
assert(legacy_data.tasks.test.command[1] == "legacy-test", "legacy task configuration changed")
local legacy_reinit, _, legacy_state = project.initialize(legacy_root, {
  validator = accept_validation,
})
assert(legacy_reinit == nil and legacy_state == "exists", "legacy configuration was overwritten")
local migrated_path = assert(project.initialize(legacy_root, {
  force = true,
  validator = accept_validation,
}))
assert(
  migrated_path == project.tasks_path(legacy_root) and vim.fn.filereadable(migrated_path) == 1,
  "explicit overwrite did not use task-config.json"
)
assert(vim.fn.filereadable(legacy_path) == 0, "explicit overwrite retained legacy tasks.json")

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
assert(config.setup().format_on_save, "QML format-on-save is not enabled by default")
local valid_format_option, format_option_error = pcall(config.setup, { format_on_save = "yes" })
assert(not valid_format_option, "invalid format_on_save configuration was accepted")
assert(
  tostring(format_option_error):find("format_on_save must be a boolean", 1, true),
  "invalid format_on_save configuration produced an unclear error"
)
local valid_filter_option, filter_option_error = pcall(config.setup, { qml_file_filter = true })
assert(not valid_filter_option, "invalid qml_file_filter configuration was accepted")
assert(
  tostring(filter_option_error):find("qml_file_filter must be a function", 1, true),
  "invalid qml_file_filter configuration produced an unclear error"
)
config.setup({
  qml_file_filter = function()
    return "yes"
  end,
})
local valid_filter_result, filter_result_error = pcall(project.detect_file, qml_path)
assert(not valid_filter_result, "non-boolean qml_file_filter result was accepted")
assert(
  tostring(filter_result_error):find("qml_file_filter must return a boolean", 1, true),
  "invalid qml_file_filter result produced an unclear error"
)
config.setup()

local fake_shell_root = vim.fs.joinpath(temp_root, "fake shell")
write(vim.fs.joinpath(fake_shell_root, "shell.qml"), { "import QtQuick", "Item {}" })
write(vim.fs.joinpath(fake_shell_root, "Commons", "qmldir"), {
  "module qs.Commons",
  "singleton Style 1.0 Style.qml",
})
local fake_style = vim.fs.joinpath(fake_shell_root, "Commons", "Style.qml")
write(fake_style, {
  "pragma Singleton",
  "import QtQuick",
  "QtObject {",
  "  readonly property QtObject spacing: QtObject {",
  "    readonly property int controlHeight: 28",
  "  }",
  "}",
})
write(vim.fs.joinpath(fake_shell_root, "Ui", "qmldir"), {
  "module qs.Ui",
  "Panel 1.0 Panel.qml",
  "PluginBarApi 1.0 PluginBarApi.qml",
})
write(vim.fs.joinpath(fake_shell_root, "Ui", "Panel.qml"), {
  "import QtQuick",
  "Item { property QtObject bar: null }",
})
write(vim.fs.joinpath(fake_shell_root, "Ui", "PluginBarApi.qml"), {
  "import QtQuick",
  "QtObject {",
  '  property color foreground: "transparent"',
  "  property var shell: null",
  "  function hideTooltip(target) {}",
  "}",
})
local qml_cache_root = vim.fs.joinpath(temp_root, "qml cache")
config.setup({ qml_import_paths = { fake_shell_root } })
local qml_import_paths, qml_import_error = require("omarchy-plugin-dev.qml").import_paths({
  cache_root = qml_cache_root,
  qt_qml_queries = {},
})
assert(qml_import_error == nil, "QML import bridge failed: " .. tostring(qml_import_error))
assert(#qml_import_paths == 2, "QML import bridge changed the resolved path count")
local bridged_shell = vim.fs.joinpath(qml_import_paths[1], "qs", "shell.qml")
assert(
  vim.uv.fs_realpath(bridged_shell)
    == project.canonical(vim.fs.joinpath(fake_shell_root, "shell.qml")),
  "QML import bridge does not expose the Quickshell root as qs"
)
local bridged_style = vim.fs.joinpath(qml_import_paths[1], "qs", "Commons", "Style.qml")
local bridged_style_text = table.concat(vim.fn.readfile(bridged_style), "\n")
assert(
  bridged_style_text:find("readonly property alias spacing", 1, true),
  "QML import bridge did not expose grouped object types"
)
assert(
  table.concat(vim.fn.readfile(fake_style), "\n"):find("property QtObject spacing", 1, true),
  "QML import bridge modified the configured shell"
)
local bridged_panel = vim.fs.joinpath(qml_import_paths[1], "qs", "Ui", "Panel.qml")
assert(
  table
    .concat(vim.fn.readfile(bridged_panel), "\n")
    :find("property PluginBarApi bar: null", 1, true),
  "QML import bridge did not expose the documented bar host type"
)
assert(
  qml_import_paths[2] == vim.fs.normalize(fake_shell_root),
  "configured QML import path was not preserved"
)

local valid_qml = vim.fs.joinpath(root, "ValidStyle.qml")
write(valid_qml, {
  "import QtQuick",
  "import qs.Commons",
  "Item { property int rowHeight: Style.spacing.controlHeight }",
})
local qml_lint = assert(require("omarchy-plugin-dev.qmllint").resolve())
local valid_lint = vim
  .system({ qml_lint.path, "-I", qml_import_paths[1], valid_qml }, { text = true })
  :wait()
local valid_lint_output = (valid_lint.stdout or "") .. (valid_lint.stderr or "")
assert(
  not valid_lint_output:find('Member "controlHeight" not found', 1, true),
  "QML import bridge left valid grouped properties unresolved"
)

local invalid_qml = vim.fs.joinpath(root, "InvalidStyle.qml")
write(invalid_qml, {
  "import QtQuick",
  "import qs.Commons",
  "Item { property int rowHeight: Style.spacing.controlHeigt }",
})
local invalid_lint = vim
  .system({ qml_lint.path, "-I", qml_import_paths[1], invalid_qml }, { text = true })
  :wait()
local invalid_lint_output = (invalid_lint.stdout or "") .. (invalid_lint.stderr or "")
assert(
  invalid_lint_output:find('Member "controlHeigt" not found', 1, true),
  "QML import bridge hid a misspelled grouped property"
)

local valid_panel_qml = vim.fs.joinpath(root, "ValidPanel.qml")
write(valid_panel_qml, {
  "import QtQuick",
  "import qs.Ui",
  "Panel {",
  "  property color hostForeground: bar ? bar.foreground : 'transparent'",
  "  property var hostShell: bar ? bar.shell : null",
  "  function hideHostTooltip() { if (bar) bar.hideTooltip(this) }",
  "}",
})
local valid_panel_lint = vim
  .system({ qml_lint.path, "-I", qml_import_paths[1], valid_panel_qml }, { text = true })
  :wait()
local valid_panel_output = (valid_panel_lint.stdout or "") .. (valid_panel_lint.stderr or "")
assert(
  not valid_panel_output:find('Member "foreground" not found', 1, true)
    and not valid_panel_output:find('Member "shell" not found', 1, true)
    and not valid_panel_output:find('Member "hideTooltip" not found', 1, true),
  "QML import bridge left documented bar host members unresolved"
)
local invalid_panel_qml = vim.fs.joinpath(root, "InvalidPanel.qml")
write(invalid_panel_qml, {
  "import QtQuick",
  "import qs.Ui",
  "Panel { property var invalidHostMember: bar ? bar.foregroun : null }",
})
local invalid_panel_lint = vim
  .system({ qml_lint.path, "-I", qml_import_paths[1], invalid_panel_qml }, { text = true })
  :wait()
local invalid_panel_output = (invalid_panel_lint.stdout or "") .. (invalid_panel_lint.stderr or "")
assert(
  invalid_panel_output:find('Member "foregroun" not found', 1, true),
  "QML import bridge hid a misspelled bar host member"
)

local fake_qt_qml = vim.fs.joinpath(temp_root, "fake Qt", "qml")
vim.fn.mkdir(fake_qt_qml, "p")
local fake_qmake = vim.fs.joinpath(temp_root, "fake qmake6")
write(fake_qmake, {
  "#!/bin/sh",
  "printf '%s\\n' \"$FAKE_QT_QML\"",
})
make_executable(fake_qmake)
vim.env.FAKE_QT_QML = fake_qt_qml
local discovered_qml_paths = require("omarchy-plugin-dev.qml").import_paths({
  cache_root = qml_cache_root,
  qt_qml_queries = { { fake_qmake, "-query", "QT_INSTALL_QML" } },
})
assert(
  discovered_qml_paths[1] == vim.fs.normalize(fake_qt_qml),
  "Qt's QML import path was not discovered"
)
vim.env.FAKE_QT_QML = nil
config.setup({
  qml_file_filter = function(context)
    return context.path ~= project.canonical(excluded_qml_path)
  end,
})

local check_spec = assert(task_specs.check(project.canonical(root)))
assert(check_spec.cwd == project.canonical(root), "check task cwd is wrong")
local validate_step = check_spec.strategy.tasks[1]
assert(
  validate_step.cmd[1]:match("/scripts/validate%-manifest$") and #validate_step.cmd == 1,
  "validation task does not use the manifest wrapper"
)
assert(
  validate_step.env.OMARCHY_PLUGIN_DEV_OMARCHY == "omarchy",
  "validation wrapper did not receive the configured Omarchy executable"
)
assert(
  vim.deep_equal(validate_step.components, { "default" }),
  "validation task still treats ordinary output as diagnostics"
)
local lint_step = check_spec.strategy.tasks[2]
local lint_info = assert(require("omarchy-plugin-dev.qmllint").resolve())
assert(lint_info.major >= 6, "automatic qmllint resolution selected a pre-Qt-6 executable")
assert(lint_step.cmd[1]:match("/scripts/lint%-qml$"), "lint task does not use the QML wrapper")
assert(
  lint_step.env.OMARCHY_PLUGIN_DEV_QMLLINT == lint_info.path,
  "lint wrapper did not receive the resolved Qt 6 qmllint"
)
assert(lint_step.cmd[2] == "-I", "lint task lost the import flag")
assert(vim.tbl_contains(lint_step.cmd, qml_js_path), "lint task omitted QML JavaScript")
assert(
  not vim.tbl_contains(lint_step.cmd, excluded_qml_path),
  "lint task included QML rejected by the ownership filter"
)
assert(
  not vim.tbl_contains(lint_step.cmd, ignored_qml_path),
  "lint task included a Git-ignored QML artifact"
)
assert(
  not vim.tbl_contains(lint_step.cmd, regular_js_path),
  "lint task included ordinary JavaScript"
)
local lint_import_paths = {}
for index, argument in ipairs(lint_step.cmd) do
  if argument == "-I" then
    lint_import_paths[#lint_import_paths + 1] = lint_step.cmd[index + 1]
  end
end
assert(vim.tbl_contains(lint_import_paths, "/usr/share/omarchy/shell"), "lint lost Omarchy imports")
local has_qs_bridge = false
for _, import_path in ipairs(lint_import_paths) do
  if
    vim.uv.fs_realpath(vim.fs.joinpath(import_path, "qs", "shell.qml"))
    == vim.uv.fs_realpath("/usr/share/omarchy/shell/shell.qml")
  then
    has_qs_bridge = true
  end
end
assert(has_qs_bridge, "lint task lost the qs namespace bridge")
assert(
  lint_step.components[1].items_only == true
    and lint_step.components[1].set_diagnostics == true
    and lint_step.components[1].errorformat ~= nil,
  "lint task does not restrict diagnostics to parsed qmllint messages"
)
local lint_items = vim.fn.getqflist({
  lines = {
    "[INFO] Linting plugin QML",
    "Warning: /tmp/Test.qml:2:3: example warning [test]",
    "source context",
  },
  efm = lint_step.components[1].errorformat,
}).items
assert(
  #lint_items == 1 and lint_items[1].valid == 1 and lint_items[1].type == "W",
  "lint errorformat did not isolate the qmllint diagnostic"
)
assert(lint_step.cwd == project.canonical(root), "lint task cwd is wrong")
config.setup()

local test_spec = assert(task_specs.test(project.canonical(root)))
assert(
  test_spec.cmd[1]:match("/scripts/run%-project%-test$") and test_spec.cmd[2] == "./scripts/test",
  "project test task does not use its output wrapper"
)
assert(test_spec.cwd == project.canonical(root), "test task cwd is wrong")
assert(
  vim.deep_equal(test_spec.components, { "default" }),
  "project test task still treats arbitrary output as diagnostics"
)

local logs_spec = assert(task_specs.logs(project.canonical(root)))
assert(logs_spec.cmd[1]:match("/scripts/shell%-logs$"), "logs task does not use its wrapper")
assert(logs_spec.cmd[2] == "_COMM=quickshell", "logs wrapper lost the journal match")
assert(logs_spec.cmd[3] == "--follow", "logs wrapper lost follow mode")
assert(
  logs_spec.env.OMARCHY_PLUGIN_DEV_JOURNALCTL == "journalctl",
  "logs wrapper did not receive the configured journalctl executable"
)

local no_test_root = vim.fs.joinpath(temp_root, "plugin without tests")
create_project(no_test_root)
local missing_test_build, missing_test_error = task_specs.build(project.canonical(no_test_root))
assert(missing_test_build == nil, "test-and-build accepted a missing test task")
assert(
  missing_test_error and missing_test_error:find("No test task is configured", 1, true),
  "test-and-build did not explain its missing test task"
)
config.setup({
  tasks = {
    build = { cmd = { "/bin/true" }, name = "Custom build" },
  },
})
local custom_build = assert(task_specs.build(project.canonical(no_test_root)))
assert(vim.deep_equal(custom_build.cmd, { "/bin/true" }), "custom build override was ignored")
config.setup({ tasks = { build = { name = "Partial build override" } } })
assert(
  task_specs.build(project.canonical(no_test_root)) == nil,
  "partial build override bypassed the required test"
)
local function_default
config.setup({
  tasks = {
    build = function(context)
      function_default = context.default
      context.default.name = "Function build"
      return context.default
    end,
  },
})
local function_build = assert(task_specs.build(project.canonical(root)))
assert(function_default ~= nil, "build function override lost its default spec")
assert(function_build.name == "Function build", "build function override was not applied")
config.setup()

local hot_reload_spec = assert(task_specs.hot_reload(project.canonical(root)))
local hot_reload_steps = hot_reload_spec.strategy.tasks
assert(#hot_reload_steps == 3, "build should check, deploy, and restart exactly once")
assert(
  hot_reload_steps[2].cmd[1]:match("/scripts/deploy$"),
  "build does not use the staged deployment helper"
)
assert(
  vim.deep_equal(hot_reload_steps[2].components, { "default" }),
  "deploy task still treats ordinary output as diagnostics"
)
assert(
  vim.tbl_contains(hot_reload_steps[2].cmd, "--enable-auto"),
  "build does not enable each deployment by default"
)
assert(
  vim.tbl_contains(hot_reload_steps[2].cmd, "--enable-first-install"),
  "build does not enable a first installation by default"
)
assert(
  hot_reload_steps[3].cmd[1]:match("/scripts/restart%-shell$"),
  "build does not use the shell restart helper"
)
assert(
  hot_reload_steps[3].env.OMARCHY_PLUGIN_DEV_OMARCHY == "omarchy",
  "shell restart helper did not receive the configured Omarchy executable"
)

config.setup({ enable_auto = false, enable_first_install = false })
local disabled_enable_spec = assert(task_specs.hot_reload(project.canonical(root)))
assert(
  not vim.tbl_contains(disabled_enable_spec.strategy.tasks[2].cmd, "--enable-auto"),
  "disabled automatic enabling remained in the deploy command"
)
assert(
  not vim.tbl_contains(disabled_enable_spec.strategy.tasks[2].cmd, "--enable-first-install"),
  "disabled first-install enabling remained in the deploy command"
)
config.setup()

local build_spec = assert(task_specs.build(project.canonical(root)))
local build_steps = build_spec.strategy.tasks
local restart_count = 0
for _, step in ipairs(build_steps) do
  if step.metadata and step.metadata.omarchy_plugin_dev_action == "restart" then
    restart_count = restart_count + 1
  end
end
assert(restart_count == 1, "test-and-build must restart the shell exactly once")
assert(
  build_steps[2].metadata.omarchy_plugin_dev_action == "test",
  "configured test was silently omitted from the build"
)
assert(
  build_steps[#build_steps].metadata.omarchy_plugin_dev_action == "restart",
  "test-and-build does not end with the shell restart"
)

config.setup()
local lsp = require("omarchy-plugin-dev.lsp")
assert(lsp.executable(), "installed canonical qmlls was not discovered")
local lsp_setup, lsp_setup_error = lsp.setup()
assert(lsp_setup, lsp_setup_error)
assert(
  vim.tbl_contains(vim.lsp.config[lsp.name].cmd, "--no-cmake-calls"),
  "qmlls still performs irrelevant CMake discovery"
)
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
  tasks.build(project.canonical(unavailable_test_root)) == nil,
  "build silently skipped an unavailable test"
)
assert(
  #notifications == 1 and notifications[1]:find("Test is unavailable", 1, true),
  "build did not explain the unavailable configured test"
)
rawset(vim, "notify", original_notify)
config.setup()

local project_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(project_buf)
vim.api.nvim_buf_set_name(project_buf, qml_js_path)
vim.api.nvim_buf_set_lines(
  project_buf,
  0,
  -1,
  false,
  { ".pragma library", "function value() { return 1 }" }
)
require("omarchy-plugin-dev.mappings").detach(project_buf)
vim.keymap.set("n", "<localleader>b", "<cmd>let g:user_mapping_ran = 1<cr>", {
  buffer = project_buf,
  desc = "User conflict",
})
vim.bo[project_buf].filetype = "javascript"
require("omarchy-plugin-dev").attach(project_buf)
assert(vim.bo[project_buf].filetype == "qmljs", "QML JavaScript filetype was not repaired")
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
require("omarchy-plugin-dev.lsp").root_dir(project_buf, function(root_dir)
  lsp_root = root_dir
end)
assert(lsp_root == project.canonical(root), "LSP root did not use the detected Omarchy project")

local original_get_clients = vim.lsp.get_clients
local original_detach_client = vim.lsp.buf_detach_client
local original_diagnostic_reset = vim.diagnostic.reset
local original_get_namespace = vim.lsp.diagnostic.get_namespace
local original_defer_fn = vim.defer_fn
local deferred_cleanups = {}
local detached_clients = {}
local reset_namespaces = {}
local stopped_clients = {}
local terminated_clients = {}
local function run_deferred(delay)
  local pending = deferred_cleanups
  deferred_cleanups = {}
  for _, deferred in ipairs(pending) do
    if deferred.delay == delay then
      deferred.callback()
    else
      deferred_cleanups[#deferred_cleanups + 1] = deferred
    end
  end
end
local function fake_client(id, name, attached_buffers)
  return {
    id = id,
    name = name,
    namespace = id + 54,
    attached_buffers = attached_buffers,
    rpc = {
      terminate = function()
        terminated_clients[#terminated_clients + 1] = id
      end,
    },
    stop = function()
      stopped_clients[#stopped_clients + 1] = id
    end,
  }
end
local generic_qml_client = fake_client(17, "qmlls", {
  [project_buf] = true,
  [998] = true,
})
local project_qml_client = fake_client(18, "omarchy_plugin_dev", { [project_buf] = true })
local javascript_client = fake_client(19, "vtsls", { [project_buf] = true, [999] = true })
vim.lsp.get_clients = function(opts)
  if not opts or opts.bufnr ~= project_buf then
    return original_get_clients(opts)
  end
  local clients = { generic_qml_client, project_qml_client, javascript_client }
  if opts.name then
    clients = vim.tbl_filter(function(client)
      return client.name == opts.name
    end, clients)
  end
  return clients
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
vim.defer_fn = function(callback, delay)
  assert(delay == 100 or delay == 1000, "competing-client cleanup used an unexpected delay")
  deferred_cleanups[#deferred_cleanups + 1] = { callback = callback, delay = delay }
end
config.setup({
  qml_file_filter = function(context)
    return context.path ~= project.canonical(qml_js_path)
  end,
})
assert(not lsp.claim(project_buf), "excluded QML buffer claimed language-server ownership")
assert(#detached_clients == 0, "excluded QML buffer detached a language client")
config.setup()
assert(lsp.claim(project_buf), "detected project buffer did not claim QML server ownership")
assert(vim.deep_equal(detached_clients, { 17, 19 }), "project detached the wrong language clients")
assert(vim.deep_equal(reset_namespaces, { 71, 73 }), "competing diagnostics were not cleared")
assert(#deferred_cleanups == 2, "competing clients were not checked after attachment settled")
generic_qml_client.attached_buffers[998] = nil
run_deferred(100)
assert(
  vim.deep_equal(stopped_clients, { 17 }),
  "unused language client was not stopped after deferred attachment cleanup"
)
assert(#deferred_cleanups == 1, "unused client did not schedule forced process cleanup")
run_deferred(1000)
assert(
  vim.deep_equal(terminated_clients, { 17 }),
  "unused language client process was not terminated after the grace period"
)
detached_clients = {}
reset_namespaces = {}
deferred_cleanups = {}
assert(lsp.release(project_buf), "excluded buffer did not release the project-aware client")
assert(vim.deep_equal(detached_clients, { 18 }), "release detached the wrong language client")
assert(vim.deep_equal(reset_namespaces, { 72 }), "release left project diagnostics behind")
assert(#deferred_cleanups == 1, "released project client was not checked after detachment")
run_deferred(100)
assert(
  vim.deep_equal(stopped_clients, { 17, 18 }),
  "released project client remained running without another buffer"
)
run_deferred(1000)
assert(
  vim.deep_equal(terminated_clients, { 17, 18 }),
  "released project process survived forced cleanup"
)
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
vim.defer_fn = original_defer_fn

local format_buf = vim.fn.bufadd(qml_path)
vim.fn.bufload(format_buf)
vim.bo[format_buf].filetype = "qml"
vim.bo[format_buf].expandtab = false
vim.bo[format_buf].shiftwidth = 2
vim.bo[format_buf].softtabstop = 2
vim.bo[format_buf].tabstop = 2
vim.b[format_buf].autoformat = true
assert(require("omarchy-plugin-dev").attach(format_buf), "detected QML buffer did not attach")
assert(vim.bo[format_buf].expandtab, "detected QML buffer still indents with tabs")
assert(vim.bo[format_buf].shiftwidth == 4, "detected QML buffer shiftwidth is not four")
assert(vim.bo[format_buf].softtabstop == 4, "detected QML buffer softtabstop is not four")
assert(vim.bo[format_buf].tabstop == 4, "detected QML buffer tabstop is not four")
assert(vim.b[format_buf].autoformat == false, "editor-wide formatting was not disabled")
assert(
  #vim.api.nvim_get_autocmds({ group = "OmarchyPluginDevFormat", buffer = format_buf }) == 1,
  "detected QML buffer has no project format-on-save hook"
)

local original_lsp_format = vim.lsp.buf.format
original_get_clients = vim.lsp.get_clients
local format_request
vim.lsp.get_clients = function(opts)
  assert(opts.bufnr == format_buf, "formatting queried the wrong buffer")
  assert(opts.name == lsp.name, "formatting queried the wrong language server")
  return { { id = 23, name = lsp.name } }
end
vim.lsp.buf.format = function(opts)
  format_request = opts
end
vim.api.nvim_exec_autocmds("BufWritePre", { buffer = format_buf })
assert(format_request, "saving detected QML did not request formatting")
assert(format_request.bufnr == format_buf, "format request targeted the wrong buffer")
assert(format_request.id == 23, "format request targeted the wrong language client")
assert(format_request.async == false, "format-on-save must finish before writing")
vim.lsp.get_clients = original_get_clients
vim.lsp.buf.format = original_lsp_format

config.setup({ format_on_save = false })
assert(require("omarchy-plugin-dev").attach(format_buf), "QML buffer failed to reattach")
assert(
  #vim.api.nvim_get_autocmds({ group = "OmarchyPluginDevFormat", buffer = format_buf }) == 0,
  "format_on_save=false left the save hook enabled"
)
assert(vim.bo[format_buf].shiftwidth == 4, "format opt-out changed QML indentation")
config.setup()
vim.api.nvim_buf_delete(format_buf, { force = true })

for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
  assert(
    not mapping.desc or not mapping.desc:find("Omarchy Plugin:", 1, true),
    "mapping leaked globally"
  )
end

vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(unrelated, "View.qml")))
vim.bo.filetype = "qml"
local unrelated_buf = vim.api.nvim_get_current_buf()
vim.bo[unrelated_buf].shiftwidth = 2
vim.b[unrelated_buf].autoformat = true
require("omarchy-plugin-dev").attach(unrelated_buf)
assert(vim.bo[unrelated_buf].shiftwidth == 2, "unrelated QML indentation was changed")
assert(vim.b[unrelated_buf].autoformat == true, "unrelated QML formatting was changed")
assert(
  not mapping_by_desc(unrelated_buf, "Omarchy Plugin: test"),
  "unrelated QML buffer received project mappings"
)
local unrelated_lsp_root
require("omarchy-plugin-dev.lsp").root_dir(unrelated_buf, function(root_dir)
  unrelated_lsp_root = root_dir
end)
assert(unrelated_lsp_root == nil, "LSP root callback claimed an unrelated QML project")

config.setup({
  qml_file_filter = function(context)
    return context.path ~= project.canonical(excluded_qml_path)
  end,
})
local excluded_buf = vim.fn.bufadd(excluded_qml_path)
vim.fn.bufload(excluded_buf)
vim.bo[excluded_buf].shiftwidth = 2
vim.b[excluded_buf].autoformat = true
vim.bo[excluded_buf].filetype = "qml"
assert(
  not require("omarchy-plugin-dev").attach(excluded_buf),
  "ownership filter did not reject the QML buffer"
)
assert(vim.bo[excluded_buf].shiftwidth == 2, "excluded QML indentation was changed")
assert(vim.b[excluded_buf].autoformat == true, "excluded QML formatting was changed")
assert(
  not mapping_by_desc(excluded_buf, "Omarchy Plugin: test"),
  "excluded QML buffer received project mappings"
)
local excluded_lsp_root
require("omarchy-plugin-dev.lsp").root_dir(excluded_buf, function(root_dir)
  excluded_lsp_root = root_dir
end)
assert(excluded_lsp_root == nil, "LSP root callback claimed excluded QML")
vim.api.nvim_buf_delete(excluded_buf, { force = true })
config.setup()

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
