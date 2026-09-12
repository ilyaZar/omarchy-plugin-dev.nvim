local M = {}

local manifest = require("omarchy_plugin_dev.manifest")

local task_fields = {
  command = true,
  description = true,
}

local reserved_task_names = {
  check = true,
  deploy = true,
  hot_reload = true,
  logs = true,
  rebuild = true,
}

local conventional_test_runners = {
  {
    command = { "./scripts/test" },
    path = "scripts/test",
  },
  {
    command = { "./tests/all.sh" },
    path = "tests/all.sh",
  },
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

M.canonical = manifest.canonical
M.start = manifest.start
M.detect = manifest.detect
M.validate_root = manifest.validate_root
M.decode_manifest = manifest.decode
M.validate_manifest = manifest.validate

function M.tasks_path(root)
  return vim.fs.joinpath(root, ".omarchy-plugin-dev", "tasks.json")
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
    if normalized == ".omarchy-plugin-dev" then
      return path, false
    end
  end

  lines[#lines + 1] = ".omarchy-plugin-dev/"
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

function M.command_path(root, command)
  if type(command) ~= "table" or type(command[1]) ~= "string" then
    return nil
  end
  local executable = command[1]
  if executable:find("/", 1, true) and not vim.startswith(executable, "/") then
    executable = vim.fs.normalize(vim.fs.joinpath(root, executable))
  end
  if vim.fn.executable(executable) ~= 1 then
    return nil
  end
  local resolved = vim.fn.exepath(executable)
  return resolved ~= "" and resolved or executable
end

function M.test_candidates(root)
  root = M.canonical(root)
  local candidates = {}
  for _, runner in ipairs(conventional_test_runners) do
    local path = vim.fs.joinpath(root, runner.path)
    if vim.fn.filereadable(path) == 1 and vim.fn.executable(path) == 1 then
      candidates[#candidates + 1] = {
        command = vim.deepcopy(runner.command),
        label = runner.command[1],
      }
    end
  end
  return candidates
end

function M.has_test_files(root)
  for _, directory in ipairs({ "test", "tests", "spec", "specs" }) do
    if #vim.fn.globpath(root, "**/" .. directory, false, true) > 0 then
      return true
    end
  end
  return false
end

function M.test_state(root)
  local data, load_error, tasks_exists = M.load_tasks(root)
  if not data then
    return {
      kind = "invalid",
      label = "invalid - " .. load_error,
      tasks_exists = tasks_exists,
    }
  end

  local definition = data.tasks.test
  if definition then
    local path = M.command_path(root, definition.command)
    if path then
      return {
        kind = "configured",
        label = "configured - " .. table.concat(definition.command, " "),
        path = path,
        tasks_exists = tasks_exists,
      }
    end
    return {
      kind = "unavailable",
      label = "configured, executable missing - " .. definition.command[1],
      tasks_exists = tasks_exists,
    }
  end

  local candidates = M.test_candidates(root)
  if #candidates > 0 then
    local labels = vim.tbl_map(function(candidate)
      return candidate.label
    end, candidates)
    return {
      candidates = candidates,
      kind = "candidate",
      label = "runner found, not configured - " .. table.concat(labels, ", "),
      tasks_exists = tasks_exists,
    }
  end
  if M.has_test_files(root) then
    return {
      kind = "unaggregated",
      label = "tests found, no aggregate runner",
      tasks_exists = tasks_exists,
    }
  end
  return {
    kind = "absent",
    label = "no conventional tests detected",
    tasks_exists = tasks_exists,
  }
end

local function validation_output(result)
  local parts = {}
  for _, value in ipairs({ result.stderr, result.stdout }) do
    value = vim.trim(value or "")
    if value ~= "" then
      parts[#parts + 1] = value
    end
  end
  return table.concat(parts, "\n")
end

local function validation_command(root)
  local executable = require("omarchy_plugin_dev.config").get().executables.omarchy
  if vim.fn.executable(executable) ~= 1 then
    return nil, string.format("cannot validate: %s is not executable", executable)
  end
  return { executable, "plugin", "validate", root }
end

function M.external_validate(root)
  local command, command_error = validation_command(root)
  if not command then
    return nil, command_error
  end
  local result = vim.system(command, { text = true }):wait(10000)
  if result.code ~= 0 then
    local detail = validation_output(result)
    if detail == "" then
      detail = "validation failed"
    end
    return nil, string.format("Omarchy validation failed: %s", detail)
  end
  return true
end

function M.external_validate_async(root, callback)
  local command, command_error = validation_command(root)
  if not command then
    vim.schedule(function()
      callback(nil, command_error)
    end)
    return
  end
  vim.system(command, { text = true, timeout = 10000 }, function(result)
    local valid = result.code == 0
    local detail = validation_output(result)
    if not valid and detail == "" then
      detail = "validation failed"
    end
    vim.schedule(function()
      callback(valid, detail ~= "" and detail or nil)
    end)
  end)
end

local function valid_test_command(command)
  if command == nil then
    return true
  end
  if type(command) ~= "table" or not vim.islist(command) or #command == 0 then
    return false
  end
  for _, argument in ipairs(command) do
    if type(argument) ~= "string" or argument == "" then
      return false
    end
  end
  return true
end

function M.initialize(root, opts)
  opts = opts or {}
  if not valid_test_command(opts.test_command) then
    return nil, "test command must be a non-empty argument array"
  end
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
  local lines
  if opts.test_command then
    lines = {
      "{",
      '  "version": 1,',
      '  "tasks": {',
      '    "test": {',
      '      "command": ' .. vim.json.encode(opts.test_command),
      "    }",
      "  }",
      "}",
    }
  else
    lines = {
      "{",
      '  "version": 1,',
      '  "tasks": {}',
      "}",
    }
  end
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
