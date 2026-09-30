local M = {}

local function check(ok, message)
  if not ok then
    error(message, 0)
  end
end

local function object(value)
  return type(value) == "table" and not vim.islist(value)
end

local function text(value)
  return type(value) == "string" and value ~= "" and not value:find("[%z\1-\31]")
end

local function fields(value, allowed)
  check(object(value), "expected an object")
  for key in pairs(value) do
    check(vim.tbl_contains(allowed, key), "unknown field " .. tostring(key))
  end
end

local function tasks(value)
  check(object(value), "tasks must be an object")
  for name, task in pairs(value) do
    check(text(name), "task names must be non-empty strings")
    check(
      not vim.tbl_contains({ "check", "hot_reload", "logs", "build" }, name),
      "reserved task name: " .. name
    )
    if name ~= "test" or task ~= false then
      fields(task, { "command", "description" })
      check(
        type(task.command) == "table" and vim.islist(task.command) and #task.command > 0,
        "command must be a non-empty argv array"
      )
      for _, argument in ipairs(task.command) do
        check(
          type(argument) == "string" and argument ~= "" and not argument:find("%z"),
          "invalid command argument"
        )
      end
      check(task.description == nil or text(task.description), "invalid task description")
    end
  end
end

local function entry(value)
  fields(value, { "name", "description", "type", "source", "destination", "ref", "tasks" })
  for _, key in ipairs({ "name", "type", "source", "destination" }) do
    check(text(value[key]), key .. " must be a non-empty string")
  end
  check(
    vim.tbl_contains({ "local-source", "symlink", "git-clone" }, value.type),
    "unknown build type"
  )
  check(value.description == nil or text(value.description), "invalid build description")
  if value.type == "git-clone" then
    check(
      value.source:sub(1, 1) ~= "-"
        and (value.source:match("^%a[%w+.-]*://.+") or value.source:match("^[%w._@%-]+:[^:].*")),
      "git-clone source must be a repository URL"
    )
  end
  if value.ref ~= nil then
    check(value.type == "git-clone", "only git-clone accepts ref")
    fields(value.ref, { "tag", "commit", "release" })
    check(vim.tbl_count(value.ref) == 1, "ref requires exactly one tag, commit, or release")
    local kind, ref = next(value.ref)
    check(text(ref), "invalid reference")
    ---@cast ref string
    if kind == "commit" then
      check(ref:match("^%x+$") and (#ref == 40 or #ref == 64), "commit must be a full object id")
    elseif kind == "release" then
      check(
        value.source:match("^https://github%.com/[^/]+/[^/]+/?$"),
        "release requires a GitHub HTTPS URL"
      )
    end
  end
  if value.tasks == nil then
    value.tasks = vim.empty_dict()
  end
  tasks(value.tasks)
end

function M.path(root)
  return vim.fs.joinpath(root, ".omarchy-plugin-dev", "task-config.json")
end

function M.decode(contents, path)
  local ok, result = pcall(function()
    local data = vim.json.decode(contents)
    check(object(data), "must contain an object")
    check(data.version == 2, "version must be the number 2; replace the old configuration")
    fields(data, { "version", "builds" })
    check(
      type(data.builds) == "table" and vim.islist(data.builds) and #data.builds > 0,
      "builds must be a non-empty array"
    )
    local names = {}
    for _, build in ipairs(data.builds) do
      entry(build)
      check(not names[build.name], "duplicate build name: " .. build.name)
      names[build.name] = true
    end
    return data
  end)
  if not ok then
    return nil, "Invalid task configuration at " .. path .. ": " .. tostring(result)
  end
  return result
end

function M.load(root)
  local path = M.path(root)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then
    return nil, "Task configuration missing or not a regular file: " .. path .. "; run :OmaDevInit"
  end
  local ok, lines = pcall(vim.fn.readfile, path, "b")
  if not ok then
    return nil, tostring(lines)
  end
  local contents = table.concat(lines, "\n")
  local data, err = M.decode(contents, path)
  return data, err, vim.fn.sha256(contents)
end

function M.absolute(root, path)
  path = vim.fs.normalize(path)
  return path:sub(1, 1) == "/" and path or vim.fs.normalize(vim.fs.joinpath(root, path))
end

function M.starter(info, command)
  local lines = { "{", '  "version": 2,', '  "builds": [' }
  local definitions = {
    { "Local project", "local-source", ".", "Build this checkout in place; never delete it." },
    {
      "Local link",
      "symlink",
      "~/.config/omarchy/plugins/" .. info.manifest.id,
      "Link Omarchy to this checkout without copying files.",
    },
  }
  for index, definition in ipairs(definitions) do
    vim.list_extend(lines, {
      "    {",
      '      "name": ' .. vim.json.encode(definition[1]) .. ",",
      '      "description": ' .. vim.json.encode(definition[4]) .. ",",
      '      "type": ' .. vim.json.encode(definition[2]) .. ",",
      '      "source": ".",',
      '      "destination": ' .. vim.json.encode(definition[3]) .. ",",
      '      "tasks": '
        .. (command and ('{"test": {"command": ' .. vim.json.encode(command) .. "}}") or "{}"),
      "    }" .. (index < #definitions and "," or ""),
    })
  end
  vim.list_extend(lines, { "  ]", "}" })
  return lines
end

return M
