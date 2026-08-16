local plugin_root = assert(vim.env.OMARCHY_QML_DEV_SMOKE_ROOT)
local unrelated_qml = assert(vim.env.OMARCHY_QML_DEV_UNRELATED_QML)
local init_root = assert(vim.env.OMARCHY_QML_DEV_INIT_ROOT)

local function mapping_by_desc(bufnr, desc)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if mapping.desc == desc then
      return mapping
    end
  end
end

vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(plugin_root, "Service.qml")))
assert(
  vim.wait(5000, function()
    return package.loaded.omarchy_qml_dev ~= nil
      and vim.b.omarchy_qml_dev_root == vim.uv.fs_realpath(plugin_root)
  end),
  "local plugin did not load through the repo-managed configuration"
)

local project_buf = vim.api.nvim_get_current_buf()
assert(vim.bo.filetype == "qml", "CLIamp QML filetype was not detected")
assert(
  not mapping_by_desc(project_buf, "Omarchy QML: check"),
  "removed check mapping was installed"
)
assert(mapping_by_desc(project_buf, "Omarchy QML: hot reload"), "hot-reload mapping is missing")
assert(mapping_by_desc(project_buf, "Omarchy QML: clean rebuild"), "rebuild mapping is missing")
assert(
  vim.wait(5000, function()
    return #vim.lsp.get_clients({ bufnr = project_buf, name = "omarchy_qml_dev" }) > 0
  end),
  "qmlls did not attach to the detected Omarchy project"
)

vim.cmd.OmaDev()
assert(vim.bo.filetype == "omarchy-qml-dev", "dashboard command did not open")
vim.cmd.close()
vim.cmd.buffer(project_buf)
vim.cmd.OmaDevHealth()
assert(vim.bo.filetype == "checkhealth", "health command did not open")
vim.cmd.close()
vim.cmd.buffer(project_buf)

require("omarchy_qml_dev.tasks").check(vim.uv.fs_realpath(plugin_root))
local overseer = require("overseer")
local check_task
assert(
  vim.wait(5000, function()
    for _, task in ipairs(overseer.list_tasks({ recent_first = true })) do
      if
        task.metadata
        and task.metadata.omarchy_qml_dev_action == "check"
        and task.metadata.omarchy_qml_dev_root == vim.uv.fs_realpath(plugin_root)
      then
        check_task = task
        return true
      end
    end
    return false
  end),
  "Check did not create a visible project Overseer task"
)
assert(check_task.cwd == vim.uv.fs_realpath(plugin_root), "Check task used the wrong root")
vim.wait(10000, function()
  return check_task:is_complete()
end)
print("live Check task status: " .. check_task.status)

require("omarchy_qml_dev").setup({
  tasks = {
    reload = function()
      return { name = "Omarchy QML: smoke reload", cmd = { "true" } }
    end,
  },
})
require("omarchy_qml_dev.tasks").check_reload(vim.uv.fs_realpath(plugin_root))
local workflow_task
assert(
  vim.wait(5000, function()
    for _, task in ipairs(overseer.list_tasks({ recent_first = true })) do
      if
        task.metadata
        and task.metadata.omarchy_qml_dev_action == "check_reload"
        and task.metadata.omarchy_qml_dev_root == vim.uv.fs_realpath(plugin_root)
      then
        workflow_task = task
        return true
      end
    end
    return false
  end),
  "Check-reload did not create an Overseer workflow"
)
assert(
  vim.wait(10000, function()
    return workflow_task:is_complete()
  end),
  "Check-reload workflow did not finish"
)
assert(workflow_task.status == "SUCCESS", "Check-reload workflow failed")
print("live Check-reload task status: " .. workflow_task.status)

vim.cmd.edit(vim.fn.fnameescape(unrelated_qml))
assert(
  vim.wait(2000, function()
    return vim.bo.filetype == "qml"
  end),
  "unrelated QML filetype missing"
)
local unrelated_buf = vim.api.nvim_get_current_buf()
require("omarchy_qml_dev").attach(unrelated_buf)
assert(vim.b.omarchy_qml_dev_root == nil, "unrelated QML project was detected")
assert(
  not mapping_by_desc(unrelated_buf, "Omarchy QML: check"),
  "unrelated QML project received mappings"
)
assert(
  #vim.lsp.get_clients({ bufnr = unrelated_buf, name = "omarchy_qml_dev" }) == 0,
  "unrelated QML project received the language server"
)

vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(init_root, "Service.qml")))
assert(
  vim.wait(3000, function()
    return vim.b.omarchy_qml_dev_root == vim.uv.fs_realpath(init_root)
  end),
  "disposable Omarchy copy was not detected"
)
vim.cmd.OmaDevInit()
local tasks_path = vim.fs.joinpath(init_root, ".omarchy-qml-dev", "tasks.json")
assert(vim.fn.filereadable(tasks_path) == 1, "initialization did not create tasks.json")
assert(
  vim.tbl_contains(vim.fn.readfile(vim.fs.joinpath(init_root, ".gitignore")), ".omarchy-qml-dev/"),
  "initialization did not add the task directory to .gitignore"
)
assert(
  require("omarchy_qml_dev.project").load_tasks(init_root),
  "initialized tasks.json is invalid"
)

print("repo-managed Neovim smoke checks passed")
