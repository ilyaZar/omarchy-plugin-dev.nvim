local plugin_root = assert(vim.env.OMARCHY_PLUGIN_DEV_SMOKE_ROOT)
local entry_points = vim.json.decode(assert(vim.env.OMARCHY_PLUGIN_DEV_ENTRY_POINTS))
local unrelated_qml = assert(vim.env.OMARCHY_PLUGIN_DEV_UNRELATED_QML)
local init_root = assert(vim.env.OMARCHY_PLUGIN_DEV_INIT_ROOT)
local canonical_root = assert(vim.uv.fs_realpath(plugin_root))

assert(type(entry_points) == "table" and #entry_points > 0, "manifest has no smoke entry points")

local function mapping_by_desc(bufnr, desc)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if mapping.desc == desc then
      return mapping
    end
  end
end

local project_buf
for _, entry_point in ipairs(entry_points) do
  local entry_path = vim.fs.joinpath(plugin_root, entry_point)
  assert(
    vim.fn.filereadable(entry_path) == 1,
    "manifest entry point is unreadable: " .. entry_point
  )
  vim.cmd.edit(vim.fn.fnameescape(entry_path))
  assert(
    vim.wait(5000, function()
      return package.loaded.omarchy_plugin_dev ~= nil
        and vim.b.omarchy_plugin_dev_root == canonical_root
    end),
    "local plugin did not attach for manifest entry point: " .. entry_point
  )

  local entry_buf = vim.api.nvim_get_current_buf()
  project_buf = project_buf or entry_buf
  assert(vim.bo.filetype == "qml", "QML filetype was not detected for " .. entry_point)
  assert(
    not mapping_by_desc(entry_buf, "Omarchy Plugin: check"),
    "removed check mapping was installed"
  )
  assert(
    mapping_by_desc(entry_buf, "Omarchy Plugin: build and restart"),
    "build mapping is missing for " .. entry_point
  )
  assert(
    mapping_by_desc(entry_buf, "Omarchy Plugin: test, build, and restart"),
    "test-and-build mapping is missing for " .. entry_point
  )
  assert(
    vim.wait(5000, function()
      return #vim.lsp.get_clients({ bufnr = entry_buf, name = "omarchy_plugin_dev" }) > 0
    end),
    "qmlls did not attach for manifest entry point: " .. entry_point
  )
  local qml_clients = vim.tbl_filter(function(client)
    return client.name == "qmlls" or client.name == "omarchy_plugin_dev"
  end, vim.lsp.get_clients({ bufnr = entry_buf }))
  assert(
    #qml_clients == 1 and qml_clients[1].name == "omarchy_plugin_dev",
    "detected project has competing QML language servers"
  )
end

vim.cmd.buffer(project_buf)

vim.cmd.OmaDev()
assert(vim.bo.filetype == "omarchy-plugin-dev", "dashboard command did not open")
local dashboard_buf = vim.api.nvim_get_current_buf()
local dashboard_lines = vim.api.nvim_buf_get_lines(dashboard_buf, 0, -1, false)
assert(
  dashboard_lines[3]:find("manifest: recognized", 1, true),
  "dashboard did not distinguish manifest recognition from official validation"
)
assert(
  vim.wait(5000, function()
    local line = vim.api.nvim_buf_get_lines(dashboard_buf, 3, 4, false)[1] or ""
    return line:find("official validation: passed", 1, true) ~= nil
  end),
  "dashboard did not report successful official validation"
)
vim.cmd.close()
vim.cmd.buffer(project_buf)
vim.cmd.OmaDevHealth()
assert(vim.bo.filetype == "checkhealth", "health command did not open")
vim.cmd.close()
vim.cmd.buffer(project_buf)

require("omarchy_plugin_dev.tasks").check(canonical_root)
local overseer = require("overseer")
local check_task
assert(
  vim.wait(5000, function()
    for _, task in ipairs(overseer.list_tasks({ recent_first = true })) do
      if
        task.metadata
        and task.metadata.omarchy_plugin_dev_action == "check"
        and task.metadata.omarchy_plugin_dev_root == canonical_root
      then
        check_task = task
        return true
      end
    end
    return false
  end),
  "Check did not create a visible project Overseer task"
)
assert(check_task.cwd == canonical_root, "Check task used the wrong root")
assert(
  vim.wait(30000, function()
    return check_task:is_complete()
  end),
  "Check task did not finish"
)
assert(
  check_task.status == require("overseer.constants").STATUS.SUCCESS,
  "Check task failed with status " .. check_task.status
)
print("live Check task status: " .. check_task.status)

vim.cmd.edit(vim.fn.fnameescape(unrelated_qml))
assert(
  vim.wait(2000, function()
    return vim.bo.filetype == "qml"
  end),
  "unrelated QML filetype missing"
)
local unrelated_buf = vim.api.nvim_get_current_buf()
require("omarchy_plugin_dev").attach(unrelated_buf)
assert(vim.b.omarchy_plugin_dev_root == nil, "unrelated QML project was detected")
assert(
  not mapping_by_desc(unrelated_buf, "Omarchy Plugin: check"),
  "unrelated QML project received mappings"
)
assert(
  #vim.lsp.get_clients({ bufnr = unrelated_buf, name = "omarchy_plugin_dev" }) == 0,
  "unrelated QML project received the language server"
)

vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(init_root, entry_points[1])))
assert(
  vim.wait(3000, function()
    return vim.b.omarchy_plugin_dev_root == vim.uv.fs_realpath(init_root)
  end),
  "disposable Omarchy copy was not detected"
)
local original_select = vim.ui.select
vim.ui.select = function(items, _, on_choice)
  on_choice(items[1])
end
vim.cmd.OmaDevInit()
vim.ui.select = original_select
local tasks_path = vim.fs.joinpath(init_root, ".omarchy-plugin-dev", "tasks.json")
assert(vim.fn.filereadable(tasks_path) == 1, "initialization did not create tasks.json")
assert(
  vim.tbl_contains(
    vim.fn.readfile(vim.fs.joinpath(init_root, ".gitignore")),
    ".omarchy-plugin-dev/"
  ),
  "initialization did not add the task directory to .gitignore"
)
local project = require("omarchy_plugin_dev.project")
local initialized_tasks = assert(project.load_tasks(init_root), "initialized tasks.json is invalid")
local candidates = project.test_candidates(init_root)
if #candidates > 0 then
  assert(initialized_tasks.tasks.test, "detected test runner was not configured")
  assert(
    vim.deep_equal(initialized_tasks.tasks.test.command, candidates[1].command),
    "initialization selected the wrong test runner"
  )
else
  assert(initialized_tasks.tasks.test == nil, "initialization invented a test runner")
end

print("repo-managed Neovim smoke checks passed")
