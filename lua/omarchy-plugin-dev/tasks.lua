local M = {}

local messages = require("omarchy-plugin-dev.messages")
local specs = require("omarchy-plugin-dev.task_specs")
local targets = require("omarchy-plugin-dev.targets")

local core_names = {
  check = true,
  hot_reload = true,
  logs = true,
  build = true,
  test = true,
}

local function executable(command, root)
  if command:find("/", 1, true) and not vim.startswith(command, "/") then
    command = vim.fs.joinpath(root, command)
  end
  return vim.fn.executable(command) == 1
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

local function overseer()
  local ok, module = pcall(require, "overseer")
  if not ok then
    messages.show("overseer.nvim is required to run Omarchy Plugin tasks", vim.log.levels.ERROR)
    return nil
  end
  return module
end

local function start(spec)
  if not spec then
    return nil
  end
  local backend = overseer()
  if not backend then
    return nil
  end
  local task = backend.new_task(spec)
  if task:start() == false then
    task:dispose(true)
    return nil
  end
  require("omarchy-plugin-dev.task_layout").open(
    backend,
    { enter = false, focus_task_id = task.id }
  )
  return task
end

local function check_tools(root)
  local executables = require("omarchy-plugin-dev.config").get().executables
  if not require_executable(executables.omarchy, root, "Check") then
    return false
  end
  local lint_info, lint_error = require("omarchy-plugin-dev.qmllint").resolve()
  if not lint_info then
    messages.show("QML lint is unavailable (" .. lint_error .. ")", vim.log.levels.ERROR)
    return false
  end
  local _, import_error = require("omarchy-plugin-dev.qml").import_paths()
  if import_error then
    messages.show(import_error, vim.log.levels.ERROR)
    return false
  end
  return true
end

local function build_tools(root)
  local executables = require("omarchy-plugin-dev.config").get().executables
  return check_tools(root)
    and require_executable(executables.jq, root, "Validation")
    and require_executable(executables.rsync, root, "Validation")
end

local function test_executable(spec)
  if type(spec.cmd) ~= "table" then
    return nil
  end
  if spec.cmd[1] and spec.cmd[1]:match("/scripts/run%-project%-test$") then
    return spec.cmd[2]
  end
  return spec.cmd[1]
end

local function show_spec_error(spec_error)
  if spec_error then
    messages.show(spec_error, vim.log.levels.ERROR)
  end
end

local function run(root, action, custom_name)
  if not overseer() then
    return nil
  end
  local context, target_error = targets.resolve(root, action == "hot_reload" or action == "build")
  if not context then
    show_spec_error(target_error)
    return nil
  end
  local override = require("omarchy-plugin-dev.config").get().tasks[action]
  local custom = type(override) == "table" and (override.cmd or override.strategy)
  if (action == "check" or action == "hot_reload" or action == "build") and not custom then
    if not build_tools(context.root) then
      return nil
    end
  end
  local spec, spec_error, test
  if action == "custom" then
    spec, spec_error = specs.custom(context.root, custom_name, context.entry.tasks)
  else
    spec, spec_error, test = specs[action](context.root, context.entry.tasks)
  end
  if not spec then
    if action == "test" and (test == "missing" or test == "disabled") then
      messages.show(
        test == "disabled" and "Tests disabled for this build"
          or "No test task configured for this build; edit task-config.json",
        vim.log.levels.INFO
      )
    else
      show_spec_error(spec_error)
    end
    return nil
  end
  local checked = type(test) == "table" and test or spec
  local command = test_executable(checked)
  if command and not require_executable(command, context.root, "Task") then
    return nil
  end
  return start(targets.decorate(spec, context))
end

function M.check(root)
  return run(root, "check")
end
function M.test(root)
  return run(root, "test")
end
function M.hot_reload(root)
  return run(root, "hot_reload")
end
function M.build(root)
  return run(root, "build")
end

function M.logs(root)
  local executable = require("omarchy-plugin-dev.config").get().executables.journalctl
  if not require_executable(executable, root, "Shell logs") then
    return nil
  end
  return start(assert(specs.logs(root)))
end

local function run_custom(root, name)
  return run(root, "custom", name)
end

local function project_task_names(root)
  local names = {}
  local seen = {}
  local context, load_error = targets.resolve(root)
  if not context then
    return {}, load_error
  end
  for name in pairs(require("omarchy-plugin-dev.config").get().tasks) do
    if not core_names[name] then
      names[#names + 1] = name
      seen[name] = true
    end
  end
  for name in pairs(context.entry.tasks) do
    if not core_names[name] and not seen[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

local function open_overseer(root)
  local backend = overseer()
  if not backend then
    return
  end
  local focused
  for _, task in ipairs(backend.list_tasks({ recent_first = true })) do
    if
      task.metadata
      and (task.metadata.omarchy_plugin_dev_project or task.metadata.omarchy_plugin_dev_root)
        == root
    then
      focused = task.id
      break
    end
  end
  require("omarchy-plugin-dev.task_layout").open(backend, { enter = true, focus_task_id = focused })
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
      label = "Build and restart",
      action = function()
        M.hot_reload(root)
      end,
    },
    {
      label = "Test, build, and restart",
      action = function()
        M.build(root)
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
        open_overseer(root)
      end,
    },
  }
  for _, name in ipairs(custom_names) do
    choices[#choices + 1] = {
      label = "Project: " .. name,
      action = function()
        run_custom(root, name)
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
