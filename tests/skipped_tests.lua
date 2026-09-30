local config = require("omarchy-plugin-dev.config")
local saved_config = vim.deepcopy(config.get())
local saved_overseer_config = package.loaded["overseer.config"]
local saved_notify = vim.notify
local base_lines = { { { "custom task card", "Normal" } } }
local overseer_config = {
  task_list = {
    render = function(_task)
      return base_lines
    end,
  },
}
package.loaded["overseer.config"] = overseer_config
local definition = require("overseer.component.omarchy_plugin_dev.skipped_tests")
local notices = {}
rawset(vim, "notify", function(message, level)
  notices[#notices + 1] = { message = message, level = level }
end)
config.setup({})

for _, detected in ipairs({ true, false }) do
  local task = {
    status = "SUCCESS",
    metadata = { omarchy_plugin_dev = true, omarchy_plugin_dev_action = "test_skipped" },
  }
  local component = definition.constructor({ detected = detected })
  component:on_init(task)
  local installed = overseer_config.task_list.render
  component:on_start(task)
  assert(overseer_config.task_list.render == installed, "renderer was wrapped twice")
  local lines = installed(task)
  assert(#base_lines == 1, "warning mutated the user's renderer output")
  assert(#lines == 3 and lines[1][1][1] == "custom task card", "card added duplicate setup text")
  assert(lines[2][1][1] == "  ⚠ WARN: TESTS SKIPPED", "warning lacks glyph or readable fallback")
  assert(lines[2][1][2] == "DiagnosticWarn", "warning does not use theme colors")
  local message = detected and "Tests detected but not configured; skipping"
    or "Tests NOT detected; skipping"
  local hint = detected and "Run :OmaDevInit to configure a test runner"
    or "Add tests and configure them with :OmaDevInit"
  assert(lines[3][1][1] == "    " .. message, "dedicated warning message changed")
  assert(task.status == "SUCCESS", "warning changed pipeline status")

  local before = #notices
  component:on_complete(task, "SUCCESS")
  assert(#notices == before + 1 and notices[#notices].level == vim.log.levels.WARN)
  assert(notices[#notices].message:find("⚠ WARN: TESTS SKIPPED", 1, true))
  assert(notices[#notices].message:find(message, 1, true))
  assert(notices[#notices].message:find(hint, 1, true))
  for _, status in ipairs({ "PENDING", "RUNNING", "FAILURE", "CANCELED" }) do
    task.status = status
    assert(installed(task) == base_lines, "unfinished or failed task showed a skip warning")
    component:on_complete(task, status)
  end
  assert(#notices == before + 1, "unsuccessful skip emitted a warning notification")
  config.setup({ notify = false })
  component:on_complete(task, "SUCCESS")
  assert(#notices == before + 1, "warning ignored notify=false")
  config.setup({})

  task.status = "SUCCESS"
  task.metadata.omarchy_plugin_dev_action = "test"
  assert(installed(task) == base_lines, "configured test received a skip warning")
  assert(installed({ status = "SUCCESS" }) == base_lines, "unrelated task rendering changed")
  task.metadata.omarchy_plugin_dev_action = "test_skipped"

  -- Reconfiguration may delegate to the old renderer.
  rawset(overseer_config.task_list, "render", function(value)
    return installed(value)
  end)
  component:on_start(task)
  assert(#overseer_config.task_list.render(task) == 3, "renderer delegation duplicated the warning")
  local replacement = { { { "replacement renderer", "Normal" } } }
  rawset(overseer_config.task_list, "render", function(_task)
    return replacement
  end)
  component:on_start(task)
  assert(overseer_config.task_list.render(task)[1][1][1] == "replacement renderer")
  rawset(overseer_config.task_list, "render", function(_task)
    return base_lines
  end)
end

rawset(vim, "notify", saved_notify)
package.loaded["overseer.config"] = saved_overseer_config
---@diagnostic disable-next-line: param-type-mismatch
config.setup(saved_config)
