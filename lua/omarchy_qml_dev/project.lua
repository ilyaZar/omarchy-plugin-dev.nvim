local M = {}

local required_manifest_fields = {
  "id",
  "name",
  "version",
  "kinds",
  "entryPoints",
}

local entry_point_for_kind = {
  bar = "bar",
  ["bar-widget"] = "barWidget",
  menu = "menu",
  overlay = "overlay",
  panel = "panel",
  service = "service",
}

local task_fields = {
  command = true,
  description = true,
}

local reserved_task_names = {
  check = true,
  check_reload = true,
  deploy = true,
  hot_reload = true,
  logs = true,
  rebuild = true,
  reload = true,
}

local function is_object(value)
  return type(value) == "table" and not vim.islist(value)
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, string.format("could not read %s: %s", path, lines)
  end
  return table.concat(lines, "\n")
end

function M.canonical(path)
  local absolute = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  local normalized = vim.fs.normalize(absolute)
  return vim.uv.fs_realpath(normalized) or normalized
end

function M.start(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return M.canonical(vim.uv.cwd())
  end
  if vim.fn.isdirectory(path) == 1 then
    return M.canonical(path)
  end
  return M.canonical(vim.fs.dirname(path))
end

function M.decode_manifest(text, source_path)
  local ok, manifest = pcall(vim.json.decode, text)
  if not ok then
    return nil, string.format("manifest.json is not valid JSON at %s: %s", source_path, manifest)
  end
  if not is_object(manifest) then
    return nil, string.format("manifest.json must contain an object at %s", source_path)
  end
  return manifest
end

function M.validate_manifest(manifest, root)
  if not is_object(manifest) then
    return nil, "manifest must be an object"
  end
  if manifest.schemaVersion ~= 1 then
    return nil, "manifest schemaVersion must be the number 1"
  end
  for _, field in ipairs(required_manifest_fields) do
    if manifest[field] == nil then
      return nil, string.format("manifest is missing required field '%s'", field)
    end
  end

  local id = manifest.id
  if type(id) ~= "string" or id == "" then
    return nil, "manifest id must be a non-empty string"
  end
  if not id:match("^[A-Za-z0-9][A-Za-z0-9._-]*$") or id:find("..", 1, true) then
    return nil, string.format("manifest id '%s' is invalid", id)
  end
  if id:match("^omarchy%.") then
    return nil, string.format("manifest id '%s' uses the reserved omarchy.* namespace", id)
  end

  if type(manifest.kinds) ~= "table" or not vim.islist(manifest.kinds) or #manifest.kinds == 0 then
    return nil, "manifest kinds must be a non-empty array"
  end
  if not is_object(manifest.entryPoints) then
    return nil, "manifest entryPoints must be an object"
  end

  if is_object(manifest.barWidget) and manifest.barWidget.defaultSection ~= nil then
    local section = manifest.barWidget.defaultSection
    if not vim.tbl_contains({ "left", "center", "right" }, section) then
      return nil, "manifest barWidget.defaultSection must be left, center, or right"
    end
  end

  for name, entry_point in pairs(manifest.entryPoints) do
    if type(entry_point) ~= "string" or entry_point == "" then
      return nil, string.format("manifest entryPoints.%s must be a non-empty string", name)
    end
    if vim.startswith(entry_point, "/") or entry_point:find("..", 1, true) then
      return nil, string.format("manifest entryPoints.%s must be a safe relative path", name)
    end
    if root and vim.fn.filereadable(vim.fs.joinpath(root, entry_point)) ~= 1 then
      return nil, string.format("manifest entry point does not exist: %s", entry_point)
    end
  end

  for _, kind in ipairs(manifest.kinds) do
    if type(kind) ~= "string" or kind == "" then
      return nil, "manifest kinds entries must be non-empty strings"
    end
    local required_entry_point = entry_point_for_kind[kind]
    if required_entry_point and manifest.entryPoints[required_entry_point] == nil then
      return nil,
        string.format("manifest kind '%s' requires entryPoints.%s", kind, required_entry_point)
    end
  end

  return true
end

function M.validate_root(root)
  root = M.canonical(root)
  local path = vim.fs.joinpath(root, "manifest.json")
  local text, read_error = read_file(path)
  if not text then
    return nil, read_error
  end
  local manifest, decode_error = M.decode_manifest(text, path)
  if not manifest then
    return nil, decode_error
  end
  local valid, validation_error = M.validate_manifest(manifest, root)
  if not valid then
    return nil, string.format("invalid Omarchy plugin manifest at %s: %s", path, validation_error)
  end
  return {
    root = root,
    manifest_path = path,
    manifest = manifest,
  }
end

function M.detect(bufnr_or_path)
  local start
  if type(bufnr_or_path) == "string" then
    local path = M.canonical(bufnr_or_path)
    start = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
  else
    start = M.start(bufnr_or_path or 0)
  end
  if not start then
    return nil, "buffer has no usable path"
  end

  local manifest_path = vim.fs.find("manifest.json", {
    upward = true,
    path = start,
    type = "file",
    limit = 1,
  })[1]
  if not manifest_path then
    return nil, "no manifest.json found in this directory or its parents"
  end
  return M.validate_root(vim.fs.dirname(manifest_path))
end

function M.tasks_path(root)
  return vim.fs.joinpath(root, ".omarchy-qml-dev", "tasks.json")
end

function M.ensure_gitignore(root)
  local path = vim.fs.joinpath(root, ".gitignore")
  local lines = {}
  if vim.fn.filereadable(path) == 1 then
    local ok, current = pcall(vim.fn.readfile, path)
    if not ok then
      return nil, nil, string.format("could not read %s: %s", path, current)
    end
    lines = current
  end

  for _, line in ipairs(lines) do
    local normalized = vim.trim(line):gsub("^/", ""):gsub("/$", "")
    if normalized == ".omarchy-qml-dev" then
      return path, false
    end
  end

  lines[#lines + 1] = ".omarchy-qml-dev/"
  local write_error = vim.fn.writefile(lines, path)
  if write_error ~= 0 then
    return nil, nil, string.format("could not update %s", path)
  end
  return path, true
end

function M.decode_tasks(text, source_path)
  local ok, data = pcall(vim.json.decode, text)
  if not ok then
    return nil, string.format("tasks.json is not valid JSON at %s: %s", source_path, data)
  end
  if not is_object(data) then
    return nil, "tasks.json must contain an object"
  end
  for key in pairs(data) do
    if key ~= "version" and key ~= "tasks" then
      return nil, string.format("tasks.json has unknown top-level field '%s'", key)
    end
  end
  if data.version ~= 1 then
    return nil, "tasks.json version must be the number 1"
  end
  if not is_object(data.tasks) then
    return nil, "tasks.json tasks must be an object"
  end

  for name, task in pairs(data.tasks) do
    if name == "" or not is_object(task) then
      return nil, string.format("task '%s' must be an object", name)
    end
    if reserved_task_names[name] then
      return nil, string.format("task name '%s' is reserved for a built-in action", name)
    end
    for field in pairs(task) do
      if not task_fields[field] then
        return nil, string.format("task '%s' has unknown field '%s'", name, field)
      end
    end
    if type(task.command) ~= "table" or not vim.islist(task.command) or #task.command == 0 then
      return nil, string.format("task '%s' command must be a non-empty argument array", name)
    end
    for index, argument in ipairs(task.command) do
      if type(argument) ~= "string" or argument == "" then
        return nil,
          string.format("task '%s' command argument %d must be a non-empty string", name, index)
      end
    end
    if task.description ~= nil and type(task.description) ~= "string" then
      return nil, string.format("task '%s' description must be a string", name)
    end
  end
  return data
end

function M.load_tasks(root)
  local path = M.tasks_path(root)
  if vim.fn.filereadable(path) ~= 1 then
    return { version = 1, tasks = {} }, nil, false
  end
  local text, read_error = read_file(path)
  if not text then
    return nil, read_error, true
  end
  local data, decode_error = M.decode_tasks(text, path)
  return data, decode_error, true
end

function M.external_validate(root)
  local executable = require("omarchy_qml_dev.config").get().executables.omarchy
  if vim.fn.executable(executable) ~= 1 then
    return nil, string.format("cannot initialize: %s is not executable", executable)
  end
  local result = vim.system({ executable, "plugin", "validate", root }, { text = true }):wait(10000)
  if result.code ~= 0 then
    local detail = vim.trim(result.stderr or result.stdout or "validation failed")
    return nil, string.format("Omarchy validation failed: %s", detail)
  end
  return true
end

function M.initialize(root, opts)
  opts = opts or {}
  local info, validation_error = M.validate_root(root)
  if not info then
    return nil, validation_error
  end
  local validator = opts.validator or M.external_validate
  local valid, external_error = validator(info.root)
  if not valid then
    return nil, external_error
  end

  local path = M.tasks_path(info.root)
  if vim.fn.filereadable(path) == 1 and not opts.force then
    return nil, string.format("configuration already exists: %s", path), "exists"
  end

  local directory = vim.fs.dirname(path)
  if vim.fn.mkdir(directory, "p") == 0 and vim.fn.isdirectory(directory) ~= 1 then
    return nil, string.format("could not create directory: %s", directory)
  end
  local lines = {
    "{",
    '  "version": 1,',
    '  "tasks": {',
    '    "test": {',
    '      "command": ["./scripts/test"]',
    "    }",
    "  }",
    "}",
  }
  local write_error = vim.fn.writefile(lines, path)
  if write_error ~= 0 then
    return nil, string.format("could not write configuration: %s", path)
  end
  local _, _, ignore_error = M.ensure_gitignore(info.root)
  if ignore_error then
    return nil, ignore_error
  end
  return path
end

return M
