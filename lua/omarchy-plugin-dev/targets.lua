local M = {}
local task_config = require("omarchy-plugin-dev.task_config")
local manifest = require("omarchy-plugin-dev.manifest")
local plugin_root =
  vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))

function M.script(name)
  return vim.fs.joinpath(plugin_root, "scripts", name)
end

local function selection_path(root)
  return vim.fs.joinpath(
    vim.fn.stdpath("state"),
    "omarchy-plugin-dev",
    "selections",
    vim.fn.sha256(root) .. ".json"
  )
end

function M.selected(root)
  local ok, name = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(selection_path(root)), "\n"))
  end)
  return ok and type(name) == "string" and name or nil
end

function M.remember(root, name)
  if M.selected(root) == name then
    return true
  end
  local path = selection_path(root)
  local made, make_error = pcall(vim.fn.mkdir, vim.fs.dirname(path), "p")
  if not made then
    return nil, tostring(make_error)
  end
  local temporary = path .. "." .. vim.fn.getpid()
  local fd, err = vim.uv.fs_open(temporary, "wx", 384)
  if not fd then
    return nil, err
  end
  local contents = vim.json.encode(name) .. "\n"
  local written, write_error = vim.uv.fs_write(fd, contents, 0)
  vim.uv.fs_close(fd)
  if written ~= #contents then
    vim.uv.fs_unlink(temporary)
    return nil, write_error or "Could not save selected target"
  end
  local saved, save_error = vim.uv.fs_rename(temporary, path)
  if not saved then
    vim.uv.fs_unlink(temporary)
  end
  return saved, save_error
end

function M.identity(path)
  local stat = vim.uv.fs_lstat(path)
  return stat and string.format("%.0f:%.0f", stat.dev, stat.ino) or "absent"
end

function M.requests(root)
  local info, err = manifest.validate_root(root)
  if not info then
    return nil, err
  end
  local data, config_error, hash = task_config.load(info.root)
  if not data then
    return nil, config_error
  end
  local protected, requests = {}, {}
  for _, entry in ipairs(data.builds) do
    if entry.type ~= "git-clone" then
      protected[#protected + 1] = task_config.absolute(info.root, entry.source)
    end
  end
  for _, entry in ipairs(data.builds) do
    local selected = vim.deepcopy(entry)
    selected.destination = task_config.absolute(info.root, entry.destination):gsub("/+$", "")
    if entry.type ~= "git-clone" then
      selected.source = task_config.absolute(info.root, entry.source)
    end
    requests[#requests + 1] = {
      project = info.root,
      id = info.manifest.id,
      entry = selected,
      protected = protected,
      config_hash = hash,
      display = entry.destination,
    }
  end
  return requests
end

function M.request(root, name)
  local requests, err = M.requests(root)
  if not requests then
    return nil, err
  end
  for _, request in ipairs(requests) do
    if request.entry.name == name then
      return request
    end
  end
  return nil, "Choose a build target in :OmaDev"
end

function M.environment()
  local executables = require("omarchy-plugin-dev.config").get().executables
  return {
    OMARCHY_PLUGIN_DEV_JQ = executables.jq,
    OMARCHY_PLUGIN_DEV_OMARCHY = executables.omarchy,
    OMARCHY_PLUGIN_DEV_RSYNC = executables.rsync,
  }
end

function M.inspect(request, confirmation)
  local ok, result = pcall(function()
    return vim
      .system({
        M.script("prepare-target"),
        confirmation and "inspect" or "status",
        vim.json.encode(request),
      }, { text = true, env = M.environment() })
      :wait(10000)
  end)
  if not ok then
    return nil, tostring(result)
  end
  if result.code ~= 0 then
    local detail = vim.trim(result.stderr or "")
    return nil, detail ~= "" and detail or ("Target inspection failed (exit " .. result.code .. ")")
  end
  local decoded, report = pcall(vim.json.decode, result.stdout or "")
  if not decoded or type(report) ~= "table" then
    return nil, "Invalid target inspection result"
  end
  return report
end

function M.context(request, report, installed)
  if M.identity(request.entry.destination) ~= report.identity then
    return nil, "Destination changed during inspection; try again"
  end
  if report.operation ~= "reuse" then
    return nil,
      "Destination is missing or does not match; select " .. request.entry.name .. " in :OmaDev"
  end
  local info, manifest_error = manifest.validate_root(request.entry.destination)
  if not info then
    return nil, manifest_error
  end
  if info.manifest.id ~= request.id then
    return nil, "Destination has a different plugin id"
  end
  local native = vim.fs.joinpath(vim.env.HOME, ".config", "omarchy", "plugins", request.id)
  if installed and vim.uv.fs_realpath(native) ~= info.root then
    if request.entry.type == "local-source" then
      return nil,
        'Local project does not install this checkout. Select a symlink target such as "Local link" in :OmaDev.'
    end
    return nil, "This destination is not currently installed: " .. request.entry.destination
  end
  return {
    project = request.project,
    root = info.root,
    id = request.id,
    entry = request.entry,
    display = request.display,
    revision = report.revision,
    dirty = report.dirty,
    identity = report.identity,
    root_identity = M.identity(info.root),
    config_hash = request.config_hash,
    installed = installed == true,
  }
end

function M.resolve(project, installed)
  project = manifest.canonical(project)
  local request, err = M.request(project, M.selected(project))
  if not request then
    return nil, err
  end
  local report, inspect_error = M.inspect(request)
  if not report then
    return nil, inspect_error
  end
  return M.context(request, report, installed)
end

function M.same(left, right)
  return left.project == right.project
    and left.root == right.root
    and left.identity == right.identity
    and left.root_identity == right.root_identity
    and left.revision == right.revision
    and left.config_hash == right.config_hash
    and vim.deep_equal(left.entry, right.entry)
end

function M.decorate(spec, context)
  if not spec then
    return nil
  end
  spec.metadata = spec.metadata or {}
  spec.metadata.omarchy_plugin_dev_target = vim.deepcopy(context)
  spec.metadata.omarchy_plugin_dev_project = context.project
  spec.components = spec.components or { "default" }
  spec.components[#spec.components + 1] = "omarchy_plugin_dev.build_target"
  local function guard(task)
    if vim.islist(task) then
      for _, child in ipairs(task) do
        if type(child) == "table" then
          guard(child)
        end
      end
      return
    end
    task.cwd = context.root
    if task.cmd then
      local command = task.cmd
      if type(command) == "string" then
        if task.args then
          command = require("overseer.shell").escape_cmd(vim.list_extend({ command }, task.args))
          task.args = nil
        end
        local shell = { vim.o.shell }
        vim.list_extend(shell, vim.split(vim.o.shellcmdflag, "%s+", { trimempty = true }))
        shell[#shell + 1] = command
        command = shell
      end
      local wrapped = {
        M.script("run-target"),
        context.id,
        context.entry.destination,
        context.root,
        context.identity,
        context.root_identity,
        tostring(context.installed),
        context.revision,
      }
      vim.list_extend(wrapped, command)
      task.cmd = wrapped
      task.env = vim.tbl_extend("force", task.env or {}, M.environment())
    end
    if type(task.strategy) == "table" and task.strategy[1] == "orchestrator" then
      for _, child in ipairs(task.strategy.tasks) do
        if type(child) == "table" then
          guard(child)
        end
      end
    end
  end
  guard(spec)
  return spec
end

return M
