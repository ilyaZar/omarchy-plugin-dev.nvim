local title = "⚠ WARN: TESTS SKIPPED"
local renderer

local function warning(detected)
  if detected then
    return "Tests detected but not configured; skipping",
      "Run :OmaDevInit to configure a test runner"
  end
  return "Tests NOT detected; skipping", "Add tests and configure them with :OmaDevInit"
end

local function install_renderer()
  local task_list = require("overseer.config").task_list
  if task_list.render == renderer then
    return
  end
  local previous = task_list.render
  renderer = function(task)
    local lines = previous(task)
    local metadata = task.metadata or {}
    local state = metadata.omarchy_plugin_dev_skipped_tests
    if
      task.status ~= "SUCCESS"
      or metadata.omarchy_plugin_dev ~= true
      or metadata.omarchy_plugin_dev_action ~= "test_skipped"
      or not state
    then
      return lines
    end
    -- A user renderer may delegate to an earlier wrapper.
    for _, line in ipairs(lines) do
      if line[1] and line[1][1] == "  " .. title then
        return lines
      end
    end
    lines = vim.deepcopy(lines)
    local message, hint = warning(state == "detected")
    lines[#lines + 1] = { { "  " .. title, "DiagnosticWarn" } }
    lines[#lines + 1] = { { "    " .. message, "Comment" } }
    lines[#lines + 1] = { { "    " .. hint, "Comment" } }
    return lines
  end
  task_list.render = renderer
end

return {
  desc = "Show a warning when Omarchy plugin tests are skipped",
  editable = false,
  params = {
    detected = { type = "boolean", default = false },
  },
  constructor = function(params)
    return {
      on_init = function(_, task)
        task.metadata.omarchy_plugin_dev_skipped_tests = params.detected and "detected" or "absent"
        install_renderer()
      end,
      on_start = function(_self, _task)
        install_renderer()
      end,
      on_complete = function(_self, _task, status)
        if status == "SUCCESS" then
          local message, hint = warning(params.detected)
          require("omarchy-plugin-dev.messages").show(
            title .. "\n" .. message .. "\n" .. hint,
            vim.log.levels.WARN
          )
        end
      end,
    }
  end,
}
