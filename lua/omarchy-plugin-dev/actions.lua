local M = {}
local init_requests = {}

local function current(bufnr)
  local info, detection_error = require("omarchy-plugin-dev.project").detect(bufnr or 0)
  if not info then
    require("omarchy-plugin-dev.messages").show(
      "Not an Omarchy plugin project: " .. detection_error,
      vim.log.levels.WARN
    )
  end
  return info
end

function M.dashboard(bufnr)
  return require("omarchy-plugin-dev.ui").dashboard(bufnr)
end

function M.test(bufnr)
  local info = current(bufnr)
  return info and require("omarchy-plugin-dev.tasks").test(info.root) or nil
end

function M.hot_reload(bufnr)
  local info = current(bufnr)
  return info and require("omarchy-plugin-dev.tasks").hot_reload(info.root) or nil
end

function M.build(bufnr)
  local info = current(bufnr)
  return info and require("omarchy-plugin-dev.tasks").build(info.root) or nil
end

function M.tasks(bufnr)
  local info = current(bufnr)
  return info and require("omarchy-plugin-dev.tasks").picker(info.root) or nil
end

function M.health()
  vim.cmd("checkhealth omarchy-plugin-dev")
end

function M.edit_config()
  local path = require("omarchy-plugin-dev.config").user_config_path()
  if not path then
    vim.cmd.help("omarchy-plugin-dev-configuration")
    return
  end
  if vim.fn.filereadable(path) ~= 1 then
    require("omarchy-plugin-dev.messages").show(
      "Config file not found: " .. path,
      vim.log.levels.WARN
    )
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

function M.edit_tasks(bufnr)
  local info = current(bufnr)
  if not info then
    return
  end
  local path = require("omarchy-plugin-dev.project").existing_tasks_path(info.root)
  if vim.fn.filereadable(path) ~= 1 then
    require("omarchy-plugin-dev.messages").show(
      "Project tasks are not initialized. Run :OmaDevInit first.",
      vim.log.levels.INFO
    )
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

function M.init_project(bufnr, opts)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  opts = opts or {}
  local info = current(bufnr)
  if not info then
    return
  end
  local project = require("omarchy-plugin-dev.project")
  local path = project.existing_tasks_path(info.root)
  local source_win = vim.api.nvim_get_current_win()
  local request = {}
  init_requests[info.root] = request
  local function active()
    return init_requests[info.root] == request
  end
  local function cancel()
    if active() then
      init_requests[info.root] = nil
    end
  end

  local function initialize(force, test_command)
    if not active() then
      return
    end
    project.initialize_async(info.root, {
      force = force,
      test_command = test_command,
      active = active,
    }, function(created, init_error)
      if not active() then
        return
      end
      cancel()
      if created then
        local message = "Created " .. created
        if test_command then
          message = message .. " with test runner " .. test_command[1]
        else
          message = message .. " without a test command"
        end
        require("omarchy-plugin-dev.messages").show(message)
        if
          not test_command
          and vim.api.nvim_win_is_valid(source_win)
          and vim.api.nvim_get_current_win() == source_win
          and vim.api.nvim_win_get_buf(source_win) == bufnr
        then
          vim.cmd.edit(vim.fn.fnameescape(created))
        end
      else
        require("omarchy-plugin-dev.messages").show(init_error, vim.log.levels.ERROR)
      end
    end)
  end

  local function choose_test_command(force)
    if not active() then
      return
    end
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
      else
        cancel()
      end
    end)
  end

  if vim.fn.filereadable(path) ~= 1 or opts.force then
    return choose_test_command(opts.force == true)
  end

  vim.ui.select({ "Keep existing file", "Overwrite task configuration" }, {
    prompt = path .. " already exists",
  }, function(choice)
    if choice == "Overwrite task configuration" then
      choose_test_command(true)
    else
      cancel()
    end
  end)
end

return M
