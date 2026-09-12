local M = {}

local function current(bufnr)
  local info, detection_error = require("omarchy_plugin_dev.project").detect(bufnr or 0)
  if not info then
    require("omarchy_plugin_dev.messages").show(
      "Not an Omarchy plugin project: " .. detection_error,
      vim.log.levels.WARN
    )
  end
  return info
end

function M.dashboard(bufnr)
  bufnr = bufnr or 0
  local info = current(bufnr)
  if info then
    return require("omarchy_plugin_dev.ui").dashboard(info, bufnr)
  end
end

function M.test(bufnr)
  local info = current(bufnr)
  return info and require("omarchy_plugin_dev.tasks").test(info.root) or nil
end

function M.hot_reload(bufnr)
  local info = current(bufnr)
  return info and require("omarchy_plugin_dev.tasks").hot_reload(info.root) or nil
end

function M.rebuild(bufnr)
  local info = current(bufnr)
  return info and require("omarchy_plugin_dev.tasks").rebuild(info.root) or nil
end

function M.tasks(bufnr)
  local info = current(bufnr)
  return info and require("omarchy_plugin_dev.tasks").picker(info.root) or nil
end

function M.health()
  vim.cmd("checkhealth omarchy-plugin-dev")
end

function M.edit_tasks(bufnr)
  local info = current(bufnr)
  if not info then
    return
  end
  local path = require("omarchy_plugin_dev.project").tasks_path(info.root)
  if vim.fn.filereadable(path) ~= 1 then
    require("omarchy_plugin_dev.messages").show(
      "Project tasks are not initialized. Run :OmaDevInit first.",
      vim.log.levels.INFO
    )
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

function M.init_project(bufnr, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  local info = current(bufnr)
  if not info then
    return
  end
  local project = require("omarchy_plugin_dev.project")
  local path = project.tasks_path(info.root)

  local function initialize(force, test_command)
    local created, init_error = project.initialize(info.root, {
      force = force,
      test_command = test_command,
    })
    if created then
      local message = "Created " .. created
      if test_command then
        message = message .. " with test runner " .. test_command[1]
      else
        message = message .. " without a test command"
      end
      require("omarchy_plugin_dev.messages").show(message)
      if not test_command then
        vim.cmd.edit(vim.fn.fnameescape(created))
      end
    else
      require("omarchy_plugin_dev.messages").show(init_error, vim.log.levels.ERROR)
    end
    return created
  end

  local function choose_test_command(force)
    local candidates = project.test_candidates(info.root)
    if #candidates == 0 then
      return initialize(force)
    end

    local choices = vim.deepcopy(candidates)
    choices[#choices + 1] = {
      label = "Create without a test command",
    }
    vim.ui.select(choices, {
      prompt = "Choose the project test runner",
      format_item = function(choice)
        return choice.label
      end,
    }, function(choice)
      if choice then
        initialize(force, choice.command)
      end
    end)
  end

  if vim.fn.filereadable(path) ~= 1 or opts.force then
    return choose_test_command(opts.force == true)
  end

  vim.ui.select({ "Keep existing file", "Overwrite tasks.json" }, {
    prompt = path .. " already exists",
  }, function(choice)
    if choice == "Overwrite tasks.json" then
      choose_test_command(true)
    end
  end)
end

return M
