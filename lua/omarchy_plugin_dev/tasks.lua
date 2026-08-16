local M = {}

local messages = require("omarchy_plugin_dev.messages")
local project = require("omarchy_plugin_dev.project")

local core_names = {
  check = true,
  deploy = true,
  hot_reload = true,
  logs = true,
  rebuild = true,
  reload = true,
  test = true,
}

local function metadata(root, action)
  return {
    omarchy_plugin_dev = true,
    omarchy_plugin_dev_action = action,
    omarchy_plugin_dev_root = root,
  }
end

local function components()
  return {
    { "on_output_quickfix", open = false, set_diagnostics = true },
    "default",
  }
end

local function executable(command, root)
  if command:find("/", 1, true) and not vim.startswith(command, "/") then
    command = vim.fs.joinpath(root, command)
  end
  return vim.fn.executable(command) == 1
end

local function plugin_root()
  local source = debug.getinfo(1, "S").source:gsub("^@", "")
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

local function deploy_command(root)
  return { vim.fs.joinpath(plugin_root(), "scripts", "deploy"), "--apply", root }
end

local function hot_reload_command()
  return { vim.fs.joinpath(plugin_root(), "scripts", "hot-reload") }
end

local function require_executable(command, root, purpose)
  if executable(command, root) then
    return true
  end
  messages.show(
    string.format("%s is unavailable (%s is not executable)", purpose, command),
    vim.log.levels.ERROR
  )
  return false
end

local function apply_override(name, root, spec)
  local override = require("omarchy_plugin_dev.config").get().tasks[name]
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

local function finalize_spec(spec, root, action, default_name)
  if not spec then
    return nil
  end
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
  local config = require("omarchy_plugin_dev.config").get()
  local validate = {
    name = "Validate Omarchy plugin manifest",
    cmd = { config.executables.omarchy, "plugin", "validate", root },
    cwd = root,
    components = components(),
    metadata = metadata(root, "validate"),
  }
  local steps = { validate }
  local qml_files = M.qml_files(root)
  if #qml_files > 0 then
    local lint_command = { config.executables.qmllint }
    for _, import_path in ipairs(config.qml_import_paths) do
      vim.list_extend(lint_command, { "-I", import_path })
    end
    vim.list_extend(lint_command, qml_files)
    steps[#steps + 1] = {
      name = "Lint Omarchy plugin QML",
      cmd = lint_command,
      cwd = root,
      components = components(),
      metadata = metadata(root, "lint"),
    }
  end
  return steps
end

function M.check_spec(root)
  local spec = {
    name = "Omarchy Plugin: check",
    cwd = root,
    strategy = { "orchestrator", tasks = M.check_steps(root) },
    components = { "default" },
    metadata = metadata(root, "check"),
  }
  return finalize_spec(apply_override("check", root, spec), root, "check", "Omarchy Plugin: check")
end

function M.test_spec(root)
  local data, load_error = project.load_tasks(root)
  if not data then
    return nil, load_error
  end
  local definition = data.tasks.test
  if not definition then
    local override = apply_override("test", root, nil)
    if override then
      return finalize_spec(override, root, "test", "Omarchy Plugin: test")
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
  return finalize_spec(apply_override("test", root, spec), root, "test", "Omarchy Plugin: test")
end

function M.reload_spec(root, opts)
  local capability = require("omarchy_plugin_dev.reload").capability(opts)
  if not capability.available then
    return nil, capability.detail
  end
  local spec = {
    name = "Omarchy Plugin: " .. capability.label,
    cmd = capability.command,
    cwd = root,
    components = { "default" },
    metadata = metadata(root, "reload"),
  }
  return finalize_spec(
    apply_override("reload", root, spec),
    root,
    "reload",
    "Omarchy Plugin: " .. capability.label
  ),
    nil,
    capability
end

function M.deploy_spec(root)
  return finalize_spec({
    name = "Deploy Omarchy plugin",
    cmd = deploy_command(root),
    cwd = root,
    components = components(),
  }, root, "deploy", "Deploy Omarchy plugin")
end

function M.restart_spec(root)
  local executable_name = require("omarchy_plugin_dev.config").get().executables.omarchy
  return finalize_spec({
    name = "Restart Omarchy shell once",
    cmd = { executable_name, "restart", "shell" },
    cwd = root,
    components = { "default" },
  }, root, "restart", "Restart Omarchy shell once")
end

function M.hot_reload_runtime_spec(root)
  return finalize_spec({
    name = "Reload deployed Omarchy plugin",
    cmd = hot_reload_command(),
    cwd = root,
    components = { "default" },
  }, root, "hot_reload_runtime", "Reload deployed Omarchy plugin")
end

function M.hot_reload_spec(root)
  local spec = {
    name = "Omarchy Plugin: hot reload",
    cwd = root,
    strategy = {
      "orchestrator",
      tasks = { M.check_spec(root), M.deploy_spec(root), M.hot_reload_runtime_spec(root) },
    },
    components = { "default" },
    metadata = metadata(root, "hot_reload"),
  }
  return finalize_spec(
    apply_override("hot_reload", root, spec),
    root,
    "hot_reload",
    "Omarchy Plugin: hot reload"
  )
end

function M.rebuild_spec(root)
  local steps = { M.check_spec(root) }
  local test_spec = M.test_spec(root)
  if test_spec and (not test_spec.cmd or executable(test_spec.cmd[1], root)) then
    steps[#steps + 1] = test_spec
  end
  steps[#steps + 1] = M.deploy_spec(root)
  steps[#steps + 1] = M.restart_spec(root)

  local spec = {
    name = "Omarchy Plugin: clean rebuild",
    cwd = root,
    strategy = { "orchestrator", tasks = steps },
    components = { "default" },
    metadata = metadata(root, "rebuild"),
  }
  return finalize_spec(
    apply_override("rebuild", root, spec),
    root,
    "rebuild",
    "Omarchy Plugin: clean rebuild"
  )
end

function M.logs_spec(root)
  local config = require("omarchy_plugin_dev.config").get()
  local command = {
    config.executables.journalctl,
    "--user",
    "-b",
    config.logs.match,
  }
  if config.logs.follow then
    command[#command + 1] = "-f"
  end
  local spec = {
    name = "Omarchy Plugin: shell logs",
    cmd = command,
    cwd = root,
    components = { "default" },
    metadata = metadata(root, "logs"),
  }
  return finalize_spec(
    apply_override("logs", root, spec),
    root,
    "logs",
    "Omarchy Plugin: shell logs"
  )
end

function M.custom_spec(root, name)
  local data, load_error = project.load_tasks(root)
  if not data then
    return nil, load_error
  end
  local definition = data.tasks[name]
  local configured = require("omarchy_plugin_dev.config").get().tasks[name]
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
    spec.name = spec.name or ("Omarchy Plugin: " .. name)
    spec.cwd = root
    spec.metadata = vim.tbl_extend("force", spec.metadata or {}, metadata(root, name))
  elseif type(configured) == "function" then
    spec = configured({ root = root, project = project })
  end
  if not spec then
    return nil, string.format("task '%s' is not defined", name)
  end
  return finalize_spec(spec, root, name, "Omarchy Plugin: " .. name)
end

local function overseer()
  local ok, module = pcall(require, "overseer")
  if not ok then
    messages.show("overseer.nvim is required to run Omarchy Plugin tasks", vim.log.levels.ERROR)
    return nil
  end
  return module
end

function M.start(spec)
  local backend = overseer()
  if not backend then
    return nil
  end
  local task = backend.new_task(spec)
  task:start()
  backend.open({ enter = false, focus_task_id = task.id })
  return task
end

local function check_tools(root)
  local config = require("omarchy_plugin_dev.config").get()
  return require_executable(config.executables.omarchy, root, "Check")
    and require_executable(config.executables.qmllint, root, "QML lint")
end

function M.check(root)
  if not check_tools(root) then
    return nil
  end
  return M.start(M.check_spec(root))
end

function M.test(root)
  local spec, spec_error, state = M.test_spec(root)
  if not spec then
    if state == "missing" then
      messages.show(
        "No test task is configured. Run :OmaDevInit, then edit " .. project.tasks_path(root),
        vim.log.levels.INFO
      )
    else
      messages.show(spec_error, vim.log.levels.ERROR)
    end
    return nil
  end
  if spec.cmd and not require_executable(spec.cmd[1], root, "Test") then
    return nil
  end
  return M.start(spec)
end

function M.reload(root)
  local spec, spec_error = M.reload_spec(root)
  if not spec then
    messages.show("Reload is unavailable: " .. spec_error, vim.log.levels.ERROR)
    return nil
  end
  if not require_executable(spec.cmd[1], root, "Reload") then
    return nil
  end
  return M.start(spec)
end

function M.hot_reload(root)
  if not check_tools(root) then
    return nil
  end
  return M.start(M.hot_reload_spec(root))
end

function M.rebuild(root)
  if not check_tools(root) then
    return nil
  end
  return M.start(M.rebuild_spec(root))
end

function M.logs(root)
  local spec = assert(M.logs_spec(root))
  if not require_executable(spec.cmd[1], root, "Shell logs") then
    return nil
  end
  return M.start(spec)
end

function M.run_custom(root, name)
  local spec, spec_error = M.custom_spec(root, name)
  if not spec then
    messages.show(spec_error, vim.log.levels.ERROR)
    return nil
  end
  if spec.cmd and not require_executable(spec.cmd[1], root, "Project task") then
    return nil
  end
  return M.start(spec)
end

local function project_task_names(root)
  local names = {}
  local seen = {}
  local data, load_error = project.load_tasks(root)
  if not data then
    return nil, load_error
  end
  for name in pairs(require("omarchy_plugin_dev.config").get().tasks) do
    if not core_names[name] then
      names[#names + 1] = name
      seen[name] = true
    end
  end
  for name in pairs(data.tasks) do
    if not core_names[name] and not seen[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

function M.open_overseer(root)
  local backend = overseer()
  if not backend then
    return
  end
  local focused
  for _, task in ipairs(backend.list_tasks({ recent_first = true })) do
    if task.metadata and task.metadata.omarchy_plugin_dev_root == root then
      focused = task.id
      break
    end
  end
  backend.open({ enter = true, focus_task_id = focused })
end

function M.picker(root)
  local custom_names, load_error = project_task_names(root)
  if not custom_names then
    messages.show(load_error, vim.log.levels.ERROR)
    return
  end
  local choices = {
    {
      label = "Check",
      action = function()
        M.check(root)
      end,
    },
    {
      label = "Test",
      action = function()
        M.test(root)
      end,
    },
    {
      label = "Hot reload",
      action = function()
        M.hot_reload(root)
      end,
    },
    {
      label = "Clean rebuild",
      action = function()
        M.rebuild(root)
      end,
    },
    {
      label = require("omarchy_plugin_dev.reload").capability().label,
      action = function()
        M.reload(root)
      end,
    },
    {
      label = "Shell logs",
      action = function()
        M.logs(root)
      end,
    },
    {
      label = "Open Overseer task list",
      action = function()
        M.open_overseer(root)
      end,
    },
  }
  for _, name in ipairs(custom_names) do
    choices[#choices + 1] = {
      label = "Project: " .. name,
      action = function()
        M.run_custom(root, name)
      end,
    }
  end
  vim.ui.select(choices, {
    prompt = "Omarchy Plugin project tasks",
    format_item = function(choice)
      return choice.label
    end,
  }, function(choice)
    if choice then
      choice.action()
    end
  end)
end

return M
