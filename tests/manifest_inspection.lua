local project = require("omarchy-plugin-dev.project")
local actions = require("omarchy-plugin-dev.actions")
local messages = require("omarchy-plugin-dev.messages")
local saved_validate = project.external_validate_async
local saved_show = messages.show
local saved_tasks = package.loaded["omarchy-plugin-dev.tasks"]
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "import QtQuick", "Item {}" }, root .. "/Service.qml")
local source_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(source_buf, root .. "/Service.qml")
local manifest = {
  schemaVersion = 1,
  id = "dev.inspection",
  name = "Inspection fixture",
  version = "1.0.0",
  kinds = { "service" },
  entryPoints = { service = "Service.qml" },
}
local function save()
  vim.fn.writefile({ vim.json.encode(manifest) }, root .. "/manifest.json")
end
save()
assert(project.detect(source_buf), "supported manifest was not detected")
assert(project.inspect(source_buf), "supported manifest could not be inspected")

project.external_validate_async = function(_, callback)
  callback(false, "unsupported schemaVersion")
end
messages.show = function() end
local task_calls = 0
package.loaded["omarchy-plugin-dev.tasks"] = {
  build = function()
    task_calls = task_calls + 1
  end,
  hot_reload = function()
    task_calls = task_calls + 1
  end,
  test = function()
    task_calls = task_calls + 1
  end,
}
for _, schema in ipairs({ 2, 42, "1" }) do
  manifest.schemaVersion = schema
  save()
  local info = assert(project.inspect(source_buf))
  assert(info.manifest.schemaVersion == schema, "inspection changed the schema")
  assert(project.detect(source_buf) == nil, "unsupported manifest passed strict detection")
  assert(project.validate_root(root) == nil, "unsupported manifest passed validation")
  local buf, win = actions.dashboard(source_buf)
  assert(buf and win, "unsupported schema blocked dashboard inspection")
  local contents = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  assert(contents:find("unsupported", 1, true), "dashboard did not identify unsupported schema")
  vim.api.nvim_win_close(win, true)
  actions.build(source_buf)
  actions.hot_reload(source_buf)
  actions.test(source_buf)
end
assert(task_calls == 0, "unsupported manifest started a task")
vim.fn.writefile({ "not json" }, root .. "/manifest.json")
local invalid, err = project.inspect(source_buf)
assert(not invalid and err:find("not valid JSON", 1, true), "inspection accepted malformed JSON")
assert(actions.dashboard(source_buf) == nil, "malformed JSON crashed or opened the dashboard")

project.external_validate_async = saved_validate
messages.show = saved_show
package.loaded["omarchy-plugin-dev.tasks"] = saved_tasks
vim.api.nvim_buf_delete(source_buf, { force = true })
assert(vim.fn.delete(root, "rf") == 0, "inspection fixture was not removed")
