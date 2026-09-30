local M = {}

M.tabs = { "Build", "Status", "Settings" }
M.actions = {
  { "h", "Build and restart", "hot_reload", "Check, deploy, then restart the shell" },
  { "b", "Test, build, restart", "build", "Check, test, deploy, then restart the shell" },
  { "t", "Test", "test", "Run the configured project test" },
  { "v", "Health", "health", "Run the plugin's health check" },
  { "p", "Project tasks", "tasks", "Choose a project task to run" },
  {
    "i",
    "Initialize project",
    "init_project",
    "Create task-config.json; confirm before replacing",
  },
  { "e", "Edit task configuration", "edit_tasks" },
  { "c", "Plugin settings", "edit_config" },
}

local function executable_status(name)
  local available = vim.fn.executable(name) == 1
  local path = available and vim.fn.exepath(name) or name
  return available and "available" or "missing", path ~= "" and path or name
end

function M.collect(bufnr)
  local project = require("omarchy-plugin-dev.project")
  local info, inspection_error = project.inspect(bufnr)
  if not info then
    return nil, inspection_error
  end
  local config = require("omarchy-plugin-dev.config")
  local options = config.get()
  local snapshot = {
    info = info,
    options = options,
    config_path = config.user_config_path(),
    tasks_path = project.existing_tasks_path(info.root),
    validation = { state = "checking" },
    tools = {},
  }
  local function add(label, value, detail, kind)
    snapshot.tools[#snapshot.tools + 1] = { label, value, kind or value, detail }
  end
  local overseer_available = pcall(require, "overseer")
  add("Overseer", overseer_available and "available" or "missing")
  add("qml-language-server", require("omarchy-plugin-dev.lsp").status(bufnr))
  add("omarchy", executable_status(options.executables.omarchy))
  local lint_state, lint_detail = require("omarchy-plugin-dev.qmllint").status()
  add("qmllint", lint_state, lint_detail)
  add("jq", executable_status(options.executables.jq))
  add("rsync", executable_status(options.executables.rsync))
  local logs_state, logs_path = executable_status(options.executables.journalctl)
  add("logs", logs_state, logs_path .. " (" .. options.logs.match .. ")")
  local test = project.test_state(info.root)
  local test_label, test_detail = test.label:match("^(.-) %- (.*)$")
  local invalid = test.kind == "invalid"
  local tasks_state = test.tasks_exists and (invalid and "invalid" or "valid") or "not initialized"
  add("project tasks", tasks_state, invalid and test_detail or nil)
  add("test task", test_label or test.label, test_detail, test.kind)
  return snapshot
end

local function column(value, width)
  return value .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(value), 1))
end

local function status_group(value)
  if vim.tbl_contains({ "missing", "failed", "invalid", "unavailable", "absent" }, value) then
    return "DiagnosticError"
  end
  if vim.tbl_contains({ "available", "running", "passed", "configured", "valid" }, value) then
    return "DiagnosticOk"
  end
  return "DiagnosticWarn"
end

local function field(label, value, group, detail, action)
  return {
    selectable = true,
    action = action,
    value = value,
    { "  " .. column(label .. ":", 22), "Normal" },
    { value, group or "Normal" },
    { detail and "  " .. detail or "", "Comment" },
  }
end

local function section(label, width)
  return {
    { "  " .. label .. " ", { "DiagnosticOk", "Bold" } },
    { string.rep("-", math.max(width - #label - 5, 0)), "Comment" },
  }
end

local function align_details(rows)
  local width = 0
  for _, row in ipairs(rows) do
    if row.value and row[3][1] ~= "" then
      width = math.max(width, vim.fn.strdisplaywidth(row.value))
    end
  end
  for _, row in ipairs(rows) do
    if row.value and row[3][1] ~= "" then
      row[2][1] = column(row.value, width + 2)
    end
  end
end

local function status_rows(snapshot, width)
  local manifest = snapshot.info.manifest
  local schema = manifest.schemaVersion
  local recognized = schema == 1
  local schema_label = type(schema) == "number" and "v" .. tostring(schema) or vim.inspect(schema)
  local id = type(manifest.id) == "string" and manifest.id or "missing id"
  local manifest_row = field(
    "manifest",
    recognized and "recognized" or "unsupported",
    recognized and "DiagnosticOk" or "DiagnosticError",
    "schema " .. schema_label .. " (" .. id .. ")"
  )
  manifest_row[3][2] = recognized and "Comment" or "Normal"
  local validation = snapshot.validation
  local rows = {
    section("Project", width),
    field("root", snapshot.info.root),
    manifest_row,
    field(
      "official validation",
      validation.state,
      status_group(validation.state),
      validation.detail
    ),
    {},
    section("Tools", width),
  }
  for _, tool in ipairs(snapshot.tools) do
    rows[#rows + 1] = field(tool[1], tool[2], status_group(tool[3]), tool[4])
  end
  align_details(rows)
  return rows
end

local function build_rows(snapshot, width)
  local rows = { section("Actions", width) }
  local label_width = 0
  for _, item in ipairs(M.actions) do
    label_width = math.max(label_width, vim.fn.strdisplaywidth(item[2]))
  end
  for _, item in ipairs(M.actions) do
    local detail = item[4]
    if item[3] == "edit_tasks" then
      detail = "Open .omarchy-plugin-dev/" .. vim.fs.basename(snapshot.tasks_path)
    elseif item[3] == "edit_config" then
      detail = snapshot.config_path and ("Open " .. vim.fs.basename(snapshot.config_path))
        or "Show configuration help"
    end
    rows[#rows + 1] = {
      action = item[3],
      { "  [" .. item[1] .. "]", "DiagnosticOk" },
      { " " .. column(item[2], label_width + 3), "Normal" },
      { detail, "Comment" },
    }
  end
  return rows
end

local function mapping_label(mappings, name)
  if not mappings or mappings.enabled == false or not mappings[name] then
    return "disabled"
  end
  return mappings[name]:gsub("^<C%-S%-(.)>$", "Ctrl+Shift+%1"):gsub("^<C%-(.)>$", "Ctrl+%1")
end

local function settings_rows(snapshot, width)
  local hint = snapshot.config_path and "Enter: edit keybindings" or "Enter: settings help"
  local rows = { section("Build keybindings", width) }
  for _, mapping in ipairs({ { "hot reload", "hot_reload" }, { "build", "build" } }) do
    rows[#rows + 1] = field(
      mapping[1],
      mapping_label(snapshot.options.mappings, mapping[2]),
      "DiagnosticInfo",
      hint,
      "edit_config"
    )
  end
  align_details(rows)
  return rows
end

function M.rows(snapshot, width)
  return {
    build_rows(snapshot, width),
    status_rows(snapshot, width),
    settings_rows(snapshot, width),
  }
end

return M
