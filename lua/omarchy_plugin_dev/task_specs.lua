local M = {}

local config = require("omarchy_plugin_dev.config")
local project = require("omarchy_plugin_dev.project")

local function metadata(root, action)
  return {
    omarchy_plugin_dev = true,
    omarchy_plugin_dev_action = action,
    omarchy_plugin_dev_root = root,
  }
end

local function components(set_diagnostics)
  if set_diagnostics == nil then
    set_diagnostics = true
  end
  return {
    { "on_output_quickfix", open = false, set_diagnostics = set_diagnostics },
    "default",
  }
end

local function plugin_root()
  local source = debug.getinfo(1, "S").source:gsub("^@", "")
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

local function deploy_command(root)
  return { vim.fs.joinpath(plugin_root(), "scripts", "deploy"), "--apply", root }
end

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

function M.qml_files(root)
  local files = vim.fn.globpath(root, "**/*.qml", false, true)
  table.sort(files)
  return files
end

function M.check_steps(root)
  local values = config.get()
  local validate = {
    name = "Validate Omarchy plugin manifest",
    cmd = { values.executables.omarchy, "plugin", "validate", root },
    cwd = root,
    components = components(),
    metadata = metadata(root, "validate"),
  }
  local steps = { validate }
  local qml_files = M.qml_files(root)
  if #qml_files > 0 then
    local lint_executable = require("omarchy_plugin_dev.qmllint").executable()
      or values.executables.qmllint
    local lint_command = { lint_executable }
    for _, import_path in ipairs(require("omarchy_plugin_dev.qml").import_paths()) do
      vim.list_extend(lint_command, { "-I", import_path })
    end
    vim.list_extend(lint_command, qml_files)
    steps[#steps + 1] = {
      name = "Lint Omarchy plugin QML",
      cmd = lint_command,
      cwd = root,
      components = components(false),
      metadata = metadata(root, "lint"),
    }
  end
  return steps
end

function M.check(root)
  local spec = {
    name = "Omarchy Plugin: check",
    cwd = root,
    strategy = { "orchestrator", tasks = M.check_steps(root) },
    components = { "default" },
    metadata = metadata(root, "check"),
  }
  return finalize(apply_override("check", root, spec), root, "check", "Omarchy Plugin: check")
end

function M.test(root)
  local data, load_error = project.load_tasks(root)
  if not data then
    return nil, load_error
  end
  local definition = data.tasks.test
  if not definition then
    local override = apply_override("test", root, nil)
    if override then
      return finalize(override, root, "test", "Omarchy Plugin: test")
    end
    return nil, nil, "missing"
  end
  local spec = {
    name = "Omarchy Plugin: test",
    cmd = vim.deepcopy(definition.command),
    cwd = root,
    components = components(),
    metadata = metadata(root, "test"),
  }
  if definition.description then
    spec.name = "Omarchy Plugin: " .. definition.description
  end
  return finalize(apply_override("test", root, spec), root, "test", "Omarchy Plugin: test")
end

function M.deploy(root)
  local executables = config.get().executables
  return finalize({
    name = "Deploy Omarchy plugin",
    cmd = deploy_command(root),
    cwd = root,
    env = {
      OMARCHY_PLUGIN_DEV_JQ = executables.jq,
      OMARCHY_PLUGIN_DEV_OMARCHY = executables.omarchy,
      OMARCHY_PLUGIN_DEV_RSYNC = executables.rsync,
    },
    components = components(),
  }, root, "deploy", "Deploy Omarchy plugin")
end

function M.restart(root)
  local executable = config.get().executables.omarchy
  return finalize({
    name = "Restart Omarchy shell once",
    cmd = { executable, "restart", "shell" },
    cwd = root,
    components = { "default" },
  }, root, "restart", "Restart Omarchy shell once")
end

function M.hot_reload(root)
  local spec = {
    name = "Omarchy Plugin: build and restart",
    cwd = root,
    strategy = {
      "orchestrator",
      tasks = { M.check(root), M.deploy(root), M.restart(root) },
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

function M.rebuild(root)
  if is_complete_table_override("rebuild") then
    return finalize(
      apply_override("rebuild", root, nil),
      root,
      "rebuild",
      "Omarchy Plugin: custom test and build"
    ),
      nil,
      nil
  end

  local steps = { M.check(root) }
  local test_spec, test_error, test_state = M.test(root)
  if test_error then
    return nil, test_error
  end
  if test_state == "missing" then
    if type(config.get().tasks.rebuild) ~= "function" then
      return nil,
        "No test task is configured. Run :OmaDevInit, then edit " .. project.tasks_path(root)
    end
  else
    test_spec = assert(test_spec)
    steps[#steps + 1] = test_spec
  end
  steps[#steps + 1] = M.deploy(root)
  steps[#steps + 1] = M.restart(root)

  local spec = {
    name = test_spec and "Omarchy Plugin: test, build, and restart"
      or "Omarchy Plugin: custom test and build",
    cwd = root,
    strategy = { "orchestrator", tasks = steps },
    components = { "default" },
    metadata = metadata(root, "rebuild"),
  }
  local finalized = finalize(
    apply_override("rebuild", root, spec),
    root,
    "rebuild",
    "Omarchy Plugin: test, build, and restart"
  )
  return finalized, nil, test_spec
end

function M.logs(root)
  local values = config.get()
  local command = {
    values.executables.journalctl,
    "--user",
    "-b",
    values.logs.match,
  }
  if values.logs.follow then
    command[#command + 1] = "-f"
  end
  local spec = {
    name = "Omarchy Plugin: shell logs",
    cmd = command,
    cwd = root,
    components = { "default" },
    metadata = metadata(root, "logs"),
  }
  return finalize(apply_override("logs", root, spec), root, "logs", "Omarchy Plugin: shell logs")
end

function M.custom(root, name)
  local data, load_error = project.load_tasks(root)
  if not data then
    return nil, load_error
  end
  local definition = data.tasks[name]
  local configured = config.get().tasks[name]
  local spec
  if definition then
    spec = {
      name = "Omarchy Plugin: " .. (definition.description or name),
      cmd = vim.deepcopy(definition.command),
      cwd = root,
      components = components(),
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
