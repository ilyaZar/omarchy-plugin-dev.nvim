local M = {}

local config = require("omarchy-plugin-dev.config")
local project = require("omarchy-plugin-dev.project")

local function metadata(root, action)
  return {
    omarchy_plugin_dev = true,
    omarchy_plugin_dev_action = action,
    omarchy_plugin_dev_root = root,
  }
end

local function lint_components()
  return {
    {
      "on_output_quickfix",
      errorformat = "%t%*[^:]: %f:%l:%c: %m,%-G%.%#",
      items_only = true,
      open_on_match = false,
      set_diagnostics = true,
    },
    "on_result_diagnostics",
    "default",
  }
end

local script_path = require("omarchy-plugin-dev.targets").script

local function apply_override(name, root, spec)
  local override = config.get().tasks[name]
  if override == nil then
    return spec
  end
  if type(override) == "function" then
    return override({ root = root, default = vim.deepcopy(spec), project = project })
  end
  if type(override) ~= "table" then
    error(string.format("omarchy-plugin-dev.nvim: tasks.%s must be a table or function", name))
  end
  return vim.tbl_extend("force", spec or {}, vim.deepcopy(override))
end

local function is_complete_table_override(name)
  local override = config.get().tasks[name]
  return type(override) == "table" and (override.cmd ~= nil or override.strategy ~= nil)
end

local function anchor_command(spec, root)
  local command = spec.cmd
  if type(command) ~= "table" or type(command[1]) ~= "string" then
    return
  end
  local executable = command[1]
  if executable:find("/", 1, true) and not vim.startswith(executable, "/") then
    command[1] = vim.fs.normalize(vim.fs.joinpath(root, executable))
  end
end

local function finalize(spec, root, action, default_name)
  if not spec then
    return nil
  end
  anchor_command(spec, root)
  spec.name = spec.name or default_name
  spec.cwd = root
  spec.metadata = vim.tbl_extend("force", spec.metadata or {}, metadata(root, action))
  return spec
end

local function git_source_files(root)
  local executable = vim.fn.exepath("git")
  if executable == "" then
    return nil
  end
  local result = vim
    .system({
      executable,
      "-C",
      root,
      "ls-files",
      "--cached",
      "--others",
      "--exclude-standard",
      "-z",
      "--",
      "*.qml",
      "*.js",
    }, { text = true })
    :wait(3000)
  if result.code ~= 0 then
    return nil
  end
  return vim.tbl_map(function(path)
    return vim.fs.joinpath(root, path)
  end, vim.split(result.stdout or "", "\0", { plain = true, trimempty = true }))
end

local function source_files(root)
  local files = git_source_files(root)
  if files then
    return files
  end
  files = vim.fn.globpath(root, "**/*.qml", false, true)
  vim.list_extend(files, vim.fn.globpath(root, "**/*.js", false, true))
  return files
end

local function qml_files(root)
  local info = assert(project.validate_root(root))
  local files = {}
  for _, path in ipairs(source_files(root)) do
    if
      vim.fn.filereadable(path) == 1
      and (path:match("%.qml$") or require("omarchy-plugin-dev.filetype").is_qml_javascript(path))
      and project.includes(path, info)
    then
      files[#files + 1] = path
    end
  end
  table.sort(files)
  return files
end

local function check_steps(root)
  local values = config.get()
  local validate = {
    name = "Validate manifest.json",
    cmd = { script_path("validate-manifest") },
    cwd = root,
    env = {
      OMARCHY_PLUGIN_DEV_OMARCHY = values.executables.omarchy,
      OMARCHY_PLUGIN_DEV_RSYNC = values.executables.rsync,
    },
    components = { "default" },
    metadata = metadata(root, "validate"),
  }
  local steps = { validate }
  local files = qml_files(root)
  if #files > 0 then
    local lint_executable = require("omarchy-plugin-dev.qmllint").executable()
      or values.executables.qmllint
    local lint_command = { script_path("lint-qml") }
    local import_paths, import_error = require("omarchy-plugin-dev.qml").import_paths()
    assert(not import_error, import_error)
    for _, import_path in ipairs(import_paths) do
      vim.list_extend(lint_command, { "-I", import_path })
    end
    vim.list_extend(lint_command, files)
    steps[#steps + 1] = {
      name = "Lint QML code",
      cmd = lint_command,
      cwd = root,
      env = {
        OMARCHY_PLUGIN_DEV_QMLLINT = lint_executable,
        OMARCHY_PLUGIN_DEV_QML_FILE_COUNT = tostring(#files),
      },
      components = lint_components(),
      metadata = metadata(root, "lint"),
    }
  end
  return steps
end

function M.check(root)
  local spec = {
    name = "Check plugin",
    cwd = root,
    strategy = { "orchestrator", tasks = check_steps(root) },
    components = { "default" },
    metadata = metadata(root, "check"),
  }
  return finalize(apply_override("check", root, spec), root, "check", "Check plugin")
end

function M.test(root, definitions)
  local definition = definitions.test
  if definition == false then
    return nil, nil, "disabled"
  end
  if not definition then
    return nil, nil, "missing"
  end
  local command = { script_path("run-project-test") }
  vim.list_extend(command, vim.deepcopy(definition.command))
  local spec = {
    name = "Test plugin",
    cmd = command,
    cwd = root,
    components = { "default" },
    metadata = metadata(root, "test"),
  }
  return finalize(spec, root, "test", "Test plugin")
end

local function restart(root)
  local executable = config.get().executables.omarchy
  return finalize({
    name = "Restart Omarchy shell",
    cmd = { script_path("restart-shell") },
    cwd = root,
    env = {
      OMARCHY_PLUGIN_DEV_OMARCHY = executable,
    },
    components = { "default" },
  }, root, "restart", "Restart Omarchy shell")
end

function M.hot_reload(root)
  local spec = {
    name = "Omarchy Plugin: build and restart",
    cwd = root,
    strategy = {
      "orchestrator",
      tasks = { M.check(root), restart(root) },
    },
    components = { "default" },
    metadata = metadata(root, "hot_reload"),
  }
  return finalize(
    apply_override("hot_reload", root, spec),
    root,
    "hot_reload",
    "Omarchy Plugin: build and restart"
  )
end

local function skipped_test(root, definitions)
  local state = project.test_state(root, definitions)
  local detected = state.kind == "candidate" or state.kind == "unaggregated"
  return finalize({
    name = "Tests skipped (not configured)",
    cmd = { script_path("skip-project-test"), detected and "detected" or "absent" },
    components = {
      { "omarchy_plugin_dev.skipped_tests", detected = detected },
      { "on_complete_notify", statuses = { "FAILURE" } },
      "default",
    },
  }, root, "test_skipped", "Tests skipped (not configured)")
end

function M.build(root, definitions)
  if is_complete_table_override("build") then
    return finalize(
      apply_override("build", root, nil),
      root,
      "build",
      "Omarchy Plugin: custom test and build"
    ),
      nil,
      nil
  end

  local steps = { M.check(root) }
  local test_spec, test_error, test_state = M.test(root, definitions)
  if test_error then
    return nil, test_error
  end
  if test_state == "missing" then
    test_spec = skipped_test(root, definitions)
  end
  if test_spec then
    steps[#steps + 1] = test_spec
  end
  steps[#steps + 1] = restart(root)

  local spec = {
    name = "Omarchy Plugin: test, build, and restart",
    cwd = root,
    strategy = { "orchestrator", tasks = steps },
    components = { "default" },
    metadata = metadata(root, "build"),
  }
  local finalized = finalize(
    apply_override("build", root, spec),
    root,
    "build",
    "Omarchy Plugin: test, build, and restart"
  )
  -- Keep custom function workflows responsible for their own prerequisites.
  if test_state == "missing" and type(config.get().tasks.build) == "function" then
    return finalized
  end
  return finalized, nil, test_spec
end

function M.logs(root)
  local values = config.get()
  local command = { script_path("shell-logs"), values.logs.match }
  if values.logs.follow then
    command[#command + 1] = "--follow"
  end
  local spec = {
    name = "Omarchy Plugin: shell logs",
    cmd = command,
    cwd = root,
    env = {
      OMARCHY_PLUGIN_DEV_JOURNALCTL = values.executables.journalctl,
    },
    components = { "default" },
    metadata = metadata(root, "logs"),
  }
  return finalize(apply_override("logs", root, spec), root, "logs", "Omarchy Plugin: shell logs")
end

function M.custom(root, name, definitions)
  local definition = definitions[name]
  local configured = config.get().tasks[name]
  local spec
  if definition then
    spec = {
      name = "Omarchy Plugin: " .. (definition.description or name),
      cmd = vim.deepcopy(definition.command),
      cwd = root,
      components = { "default" },
      metadata = metadata(root, name),
    }
  elseif type(configured) == "table" then
    spec = vim.deepcopy(configured)
  elseif type(configured) == "function" then
    spec = configured({ root = root, project = project })
  end
  if not spec then
    return nil, string.format("task '%s' is not defined", name)
  end
  return finalize(spec, root, name, "Omarchy Plugin: " .. name)
end

return M
