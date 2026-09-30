local M = {}

local manifest = require("omarchy-plugin-dev.manifest")

local task_config = require("omarchy-plugin-dev.task_config")

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

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, string.format("could not read %s: %s", path, lines)
  end
  return table.concat(lines, "\n")
end

M.canonical = manifest.canonical
M.detect = manifest.detect
M.inspect = manifest.inspect
M.validate_root = manifest.validate_root

local function file_path(bufnr_or_path)
  if type(bufnr_or_path) == "string" then
    return M.canonical(bufnr_or_path)
  end
  local bufnr = bufnr_or_path or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  return path ~= "" and M.canonical(path) or nil
end

function M.includes(bufnr_or_path, info)
  local path = file_path(bufnr_or_path)
  if not path then
    return false
  end
  info = info or M.detect(bufnr_or_path)
  if not info then
    return false
  end

  local filter = require("omarchy-plugin-dev.config").get().qml_file_filter
  if not filter then
    return true
  end
  local relative_path = vim.fs.relpath(info.root, path)
  if not relative_path then
    return false
  end
  local included = filter({
    manifest = vim.deepcopy(info.manifest),
    path = path,
    relative_path = relative_path,
    root = info.root,
  })
  if type(included) ~= "boolean" then
    error("omarchy-plugin-dev.nvim: qml_file_filter must return a boolean")
  end
  return included
end

function M.detect_file(bufnr_or_path)
  local info, detection_error = M.detect(bufnr_or_path)
  if not info then
    return nil, detection_error
  end
  if not M.includes(bufnr_or_path, info) then
    return nil, "QML file is not owned by this Omarchy plugin project"
  end
  return info
end

M.tasks_path = task_config.path
M.decode_tasks = task_config.decode
M.load_tasks = task_config.load

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

local function command_path(root, command)
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

local function has_test_files(root)
  local directories = { "test", "tests", "spec", "specs" }
  local git = vim.fn.exepath("git")
  if git ~= "" then
    local command =
      { git, "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--" }
    for _, directory in ipairs(directories) do
      command[#command + 1] = ":(glob)**/" .. directory .. "/**"
    end
    local result = vim.system(command, { text = true }):wait(3000)
    if result.code == 0 then
      for _, path in
        ipairs(vim.split(result.stdout or "", "\0", { plain = true, trimempty = true }))
      do
        if vim.fn.filereadable(vim.fs.joinpath(root, path)) == 1 then
          return true
        end
      end
      return false
    end
  end
  for _, directory in ipairs(directories) do
    if #vim.fn.globpath(root, "**/" .. directory, false, true) > 0 then
      return true
    end
  end
  return false
end

function M.test_state(root, definitions)
  local tasks_exists = vim.uv.fs_stat(M.tasks_path(root)) ~= nil
  if definitions == nil then
    local context, load_error = require("omarchy-plugin-dev.targets").resolve(root)
    if not context then
      return { kind = "invalid", label = "invalid - " .. load_error, tasks_exists = tasks_exists }
    end
    root, definitions = context.root, context.entry.tasks
  end
  local definition = definitions.test
  if definition == false then
    return {
      kind = "disabled",
      label = "tests disabled for this build",
      tasks_exists = tasks_exists,
    }
  end
  if definition then
    local path = command_path(root, definition.command)
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
  if has_test_files(root) then
    return {
      kind = "unaggregated",
      label = "tests found, no aggregate runner",
      tasks_exists = tasks_exists,
    }
  end
  return {
    kind = "absent",
    label = "tests NOT detected",
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
  local executable = require("omarchy-plugin-dev.config").get().executables.omarchy
  if vim.fn.executable(executable) ~= 1 then
    return nil, string.format("cannot validate: %s is not executable", executable)
  end
  return { executable, "plugin", "validate", root }
end

local function external_validate(root)
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
    if result.code == 124 then
      detail = "validation timed out after 10 seconds"
    elseif not valid and detail == "" then
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

local function write_tasks(root, opts)
  local path = M.tasks_path(root)
  local existing_path = path
  if vim.fn.filereadable(existing_path) == 1 and not opts.force then
    return nil, string.format("configuration already exists: %s", existing_path), "exists"
  end

  local directory = vim.fs.dirname(path)
  if vim.fn.mkdir(directory, "p") == 0 and vim.fn.isdirectory(directory) ~= 1 then
    return nil, string.format("could not create directory: %s", directory)
  end
  local lines = task_config.starter(assert(M.validate_root(root)), opts.test_command)
  local write_error = vim.fn.writefile(lines, path)
  if write_error ~= 0 then
    return nil, string.format("could not write configuration: %s", path)
  end
  local _, _, ignore_error = M.ensure_gitignore(root)
  if ignore_error then
    return nil, ignore_error
  end
  return path
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
  local validator = opts.validator or external_validate
  local valid, external_error = validator(info.root)
  if not valid then
    return nil, external_error
  end

  return write_tasks(info.root, opts)
end

function M.initialize_async(root, opts, callback)
  opts = opts or {}
  if not valid_test_command(opts.test_command) then
    return vim.schedule(function()
      callback(nil, "test command must be a non-empty argument array")
    end)
  end
  local info, validation_error = M.validate_root(root)
  if not info then
    return vim.schedule(function()
      callback(nil, validation_error)
    end)
  end

  local approved_path = M.tasks_path(info.root)
  local approved_content
  if opts.force and vim.fn.filereadable(approved_path) == 1 then
    approved_content, validation_error = read_file(approved_path)
    if not approved_content then
      return vim.schedule(function()
        callback(nil, validation_error)
      end)
    end
  end

  M.external_validate_async(info.root, function(valid, detail)
    if opts.active and not opts.active() then
      return
    end
    if not valid then
      local message = detail or "validation failed"
      callback(nil, valid == nil and message or "Omarchy validation failed: " .. message)
      return
    end
    local current_info, current_error = M.validate_root(info.root)
    if not current_info then
      callback(nil, current_error)
      return
    end
    if opts.force then
      local current_path = M.tasks_path(info.root)
      local current_content = vim.fn.filereadable(current_path) == 1 and read_file(current_path)
        or nil
      if current_path ~= approved_path or current_content ~= approved_content then
        callback(nil, "task configuration changed during validation; run initialization again")
        return
      end
    end
    callback(write_tasks(info.root, opts))
  end)
end

return M
