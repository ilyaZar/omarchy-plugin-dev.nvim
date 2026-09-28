local M = {}

local messages = require("omarchy_plugin_dev.messages")
local project = require("omarchy_plugin_dev.project")
local specs = require("omarchy_plugin_dev.task_specs")

local core_names = {
  check = true,
  deploy = true,
  hot_reload = true,
  logs = true,
  rebuild = true,
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
  task:start()
  backend.open({ enter = false, focus_task_id = task.id })
  return task
end

local function check_tools(root)
  local executables = require("omarchy_plugin_dev.config").get().executables
  if not require_executable(executables.omarchy, root, "Check") then
    return false
  end
  local lint_info, lint_error = require("omarchy_plugin_dev.qmllint").resolve()
  if not lint_info then
    messages.show("QML lint is unavailable (" .. lint_error .. ")", vim.log.levels.ERROR)
    return false
  end
  return true
end

local function build_tools(root)
  local executables = require("omarchy_plugin_dev.config").get().executables
  return check_tools(root)
    and require_executable(executables.jq, root, "Deployment")
    and require_executable(executables.rsync, root, "Deployment")
end

local function show_spec_error(spec_error)
  if spec_error then
    messages.show(spec_error, vim.log.levels.ERROR)
  end
end

function M.check(root)
  if not check_tools(root) then
    return nil
  end
  return start(specs.check(root))
end

function M.test(root)
  local spec, spec_error, state = specs.test(root)
  if not spec then
    if state == "missing" then
      messages.show(
        "No test task is configured. Run :OmaDevInit, then edit " .. project.tasks_path(root),
        vim.log.levels.INFO
      )
    else
      show_spec_error(spec_error)
    end
    return nil
  end
  if spec.cmd and not require_executable(spec.cmd[1], root, "Test") then
    return nil
  end
  return start(spec)
end

function M.hot_reload(root)
  if not build_tools(root) then
    return nil
  end
  return start(specs.hot_reload(root))
end

function M.rebuild(root)
  local spec, spec_error, test_spec = specs.rebuild(root)
  if not spec then
    show_spec_error(spec_error)
    return nil
  end
  if test_spec then
    if not build_tools(root) then
      return nil
    end
    if test_spec.cmd and not require_executable(test_spec.cmd[1], root, "Test") then
      return nil
    end
  end
  return start(spec)
end

function M.logs(root)
  local spec = assert(specs.logs(root))
  if not require_executable(spec.cmd[1], root, "Shell logs") then
    return nil
  end
  return start(spec)
end

local function run_custom(root, name)
  local spec, spec_error = specs.custom(root, name)
  if not spec then
    show_spec_error(spec_error)
    return nil
  end
  if spec.cmd and not require_executable(spec.cmd[1], root, "Project task") then
    return nil
  end
  return start(spec)
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

local function open_overseer(root)
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
      label = "Build and restart",
      action = function()
        M.hot_reload(root)
      end,
    },
    {
      label = "Test, build, and restart",
      action = function()
        M.rebuild(root)
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
