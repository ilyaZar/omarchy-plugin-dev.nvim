local M = {}

local function current(bufnr)
  local info, detection_error = require("omarchy_qml_dev.project").detect(bufnr or 0)
  if not info then
    require("omarchy_qml_dev.messages").show(
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
    return require("omarchy_qml_dev.ui").dashboard(info, bufnr)
  end
end

function M.test(bufnr)
  local info = current(bufnr)
  return info and require("omarchy_qml_dev.tasks").test(info.root) or nil
end

function M.hot_reload(bufnr)
  local info = current(bufnr)
  return info and require("omarchy_qml_dev.tasks").hot_reload(info.root) or nil
end

function M.rebuild(bufnr)
  local info = current(bufnr)
  return info and require("omarchy_qml_dev.tasks").rebuild(info.root) or nil
end

function M.health()
  vim.cmd("checkhealth omarchy-qml-dev")
end

function M.edit_tasks(bufnr)
  local info = current(bufnr)
  if not info then
    return
  end
  local path = require("omarchy_qml_dev.project").tasks_path(info.root)
  if vim.fn.filereadable(path) ~= 1 then
    require("omarchy_qml_dev.messages").show(
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
  local project = require("omarchy_qml_dev.project")
  local path = project.tasks_path(info.root)

  local function initialize(force)
    local created, init_error = project.initialize(info.root, { force = force })
    if created then
      require("omarchy_qml_dev.messages").show("Created " .. created)
    else
      require("omarchy_qml_dev.messages").show(init_error, vim.log.levels.ERROR)
    end
    return created
  end

  if vim.fn.filereadable(path) ~= 1 or opts.force then
    return initialize(opts.force == true)
  end

  vim.ui.select({ "Keep existing file", "Overwrite tasks.json" }, {
    prompt = path .. " already exists",
  }, function(choice)
    if choice == "Overwrite tasks.json" then
      initialize(true)
    end
  end)
end

return M
