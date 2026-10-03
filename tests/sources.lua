---@diagnostic disable: duplicate-set-field
local sources = require("omarchy-plugin-dev.sources")
local targets = require("omarchy-plugin-dev.targets")
local confirm = require("omarchy-plugin-dev.confirm")
local saved_request = targets.request
local saved_context = targets.context
local saved_system = vim.system
local saved_open = confirm.open
local captured
local request = {
  project = "/tmp/editor-project",
  id = "dev.example",
  entry = {
    name = "Local link",
    type = "symlink",
    source = "/tmp/editor-project",
    destination = "/tmp/installed-plugin",
    tasks = {},
  },
  protected = { "/tmp/editor-project" },
  config_hash = "fixture",
}
local report = {
  operation = "replace",
  kind = "installed-copy",
  identity = "1:2",
  fingerprint = "fixture",
  revision = "",
  branch = "",
  modified = 0,
  untracked = 0,
  ignored = 0,
  ahead = "unknown",
  comparison = "unknown",
  destructive = true,
}

targets.request = function()
  return vim.deepcopy(request)
end
targets.context = function()
  return {}
end
vim.system = function(argv, opts, callback)
  if argv[1]:match("/scripts/prepare%-target$") then
    assert(argv[2] == "inspect", "source selection skipped inspection")
    callback({ code = 0, stdout = vim.json.encode(report), stderr = "" })
    return {}
  end
  return saved_system(argv, opts, callback)
end
confirm.open = function(title, context, callback)
  captured = { title = title, context = context, callback = callback }
end

sources.choose({ root = request.project, manifest = { id = request.id } }, request.entry.name)
assert(
  vim.wait(1000, function()
    return captured ~= nil
  end),
  "replacement confirmation did not open"
)
assert(captured.title == "Select build target?", "replacement confirmation title changed")
assert(captured.context.default_no, "destructive replacement does not default to No")
local fields = {}
for _, field in ipairs(captured.context.fields) do
  fields[field[1]] = field[2]
end
assert(fields["Proposed source"] == request.entry.source, "confirmation hides the proposed source")
assert(fields.Destination == request.entry.destination, "confirmation hides the exact destination")
local notes = table.concat(captured.context.info, "\n")
assert(notes:find("Permanently delete", 1, true), "confirmation omits permanent deletion")
assert(notes:find("every file inside", 1, true), "confirmation omits directory consequences")
assert(notes:find("No backup or rollback", 1, true), "confirmation implies recovery is available")
assert(
  notes:find("Plugin-local settings", 1, true),
  "confirmation hides plugin-local settings loss"
)
assert(
  notes:find("External Omarchy shell settings", 1, true),
  "external settings are not distinguished"
)
captured.callback(false)

targets.request = saved_request
targets.context = saved_context
vim.system = saved_system
confirm.open = saved_open

local answer
local buf, win = confirm.open(captured.title, captured.context, function(value)
  answer = value
end)
assert(
  vim.api.nvim_win_get_cursor(win)[1] == vim.api.nvim_buf_line_count(buf),
  "No is not selected"
)
assert(vim.api.nvim_get_current_line():find("[N]o", 1, true), "default selection is not No")
local enter
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
  if mapping.lhs == "<CR>" then
    enter = mapping.callback
    break
  end
end
assert(enter, "confirmation Enter mapping is missing")
enter()
assert(answer == false, "Enter approved the default destructive choice")
