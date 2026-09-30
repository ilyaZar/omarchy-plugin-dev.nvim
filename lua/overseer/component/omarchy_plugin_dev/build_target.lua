local renderer

local function install_renderer()
  local task_list = require("overseer.config").task_list
  if task_list.render == renderer then
    return
  end
  local previous = task_list.render
  renderer = function(task)
    local lines = previous(task)
    local context = (task.metadata or {}).omarchy_plugin_dev_target
    if not context then
      return lines
    end
    for _, line in ipairs(lines) do
      if line[1] and line[1][1] == "  INFO: BUILD TARGET" then
        return lines
      end
    end
    lines = vim.deepcopy(lines)
    lines[#lines + 1] = { { "  INFO: BUILD TARGET", "DiagnosticInfo" } }
    local fields = {
      { "Name", context.entry.name },
      { "Type", context.entry.type },
      { "Destination", context.display },
      { "Resolved", context.root },
      {
        "Revision",
        (context.revision ~= "" and context.revision:sub(1, 8) or "not a Git checkout")
          .. (context.dirty and " (dirty)" or ""),
      },
    }
    for _, field in ipairs(fields) do
      lines[#lines + 1] =
        { { string.format("    %-14s", field[1] .. ":"), "Comment" }, { field[2], "Normal" } }
    end
    if context.entry.tasks.test == false and task.metadata.omarchy_plugin_dev_action == "build" then
      lines[#lines + 1] = { { "    Tests disabled for this build", "DiagnosticInfo" } }
    end
    return lines
  end
  task_list.render = renderer
end

local function release(self)
  if self.release then
    self.release()
    self.release = nil
  end
end

return {
  desc = "Capture the build target and hold its operation lock",
  editable = false,
  constructor = function()
    return {
      on_init = function()
        install_renderer()
      end,
      on_pre_start = function(self, task)
        local ok, err = pcall(function()
          local context = assert(task.metadata.omarchy_plugin_dev_target, "Build target is missing")
          local acquired, lock_error = require("omarchy-plugin-dev.operation").acquire(context.id)
          assert(acquired, lock_error)
          self.release = acquired
          local targets = require("omarchy-plugin-dev.targets")
          local current, target_error = targets.resolve(context.project, context.installed)
          assert(current, target_error)
          assert(
            targets.same(context, current),
            "Build target changed; start a new task from :OmaDev"
          )
        end)
        if not ok then
          release(self)
          require("omarchy-plugin-dev.messages").show(tostring(err), vim.log.levels.ERROR)
          return false
        end
      end,
      on_status = function(self, _, status)
        if status == "PENDING" then
          release(self)
        end
      end,
      on_complete = release,
      on_dispose = release,
    }
  end,
}
