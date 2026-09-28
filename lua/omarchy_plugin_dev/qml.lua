local M = {}

local bridge_version = "2"
local qt_qml_queries = {
  { "qtpaths6", "--query", "QT_INSTALL_QML" },
  { "qmake6", "-query", "QT_INSTALL_QML" },
  { "qmake-qt6", "-query", "QT_INSTALL_QML" },
  { "qtpaths", "--qt-version", "6", "--query", "QT_INSTALL_QML" },
}

local function add_unique(paths, seen, path)
  path = vim.fs.normalize(path)
  if not seen[path] then
    seen[path] = true
    paths[#paths + 1] = path
  end
end

local function entries(path)
  local result = vim.fn.readdir(path)
  table.sort(result)
  return result
end

local function qt_qml_import_path(queries)
  for _, query in ipairs(queries or qt_qml_queries) do
    local executable = vim.fn.exepath(query[1])
    if executable ~= "" then
      local command = vim.deepcopy(query)
      command[1] = executable
      local result = vim.system(command, { text = true }):wait(2000)
      local path = vim.trim(result.stdout or "")
      if result.code == 0 and path ~= "" and vim.fn.isdirectory(path) == 1 then
        return vim.fs.normalize(path)
      end
    end
  end
end

local function is_quickshell_root(path)
  return vim.fn.filereadable(vim.fs.joinpath(path, "shell.qml")) == 1
    and vim.fn.isdirectory(vim.fs.joinpath(path, "Commons")) == 1
end

local function source_signature(shell_root)
  local parts = { bridge_version, vim.uv.fs_realpath(shell_root) or vim.fs.normalize(shell_root) }
  for _, name in ipairs(entries(shell_root)) do
    parts[#parts + 1] = name
  end
  local commons = vim.fs.joinpath(shell_root, "Commons")
  for _, name in ipairs(entries(commons)) do
    local path = vim.fs.joinpath(commons, name)
    local stat = vim.uv.fs_stat(path)
    parts[#parts + 1] =
      table.concat({ name, stat and stat.type or "missing", stat and stat.size or 0 }, ":")
    if stat and stat.type == "file" then
      parts[#parts + 1] = vim.fn.sha256(table.concat(vim.fn.readfile(path, "b"), "\n"))
    end
  end
  return vim.fn.sha256(table.concat(parts, "\n"))
end

local function remove_path(path)
  local stat = vim.uv.fs_lstat(path)
  if not stat then
    return true
  end
  if stat.type == "link" then
    return vim.uv.fs_unlink(path)
  end
  return vim.fn.delete(path, "rf") == 0
end

local function link(source, target)
  local stat = vim.uv.fs_stat(source)
  if not stat then
    return nil, "source path disappeared: " .. source
  end
  return vim.uv.fs_symlink(source, target, { dir = stat.type == "directory" })
end

-- Static aliases let qmllint inspect properties on grouped QtObjects.
local function tooling_lines(path)
  local lines = vim.fn.readfile(path)
  local result = {}
  local changed = false
  for _, line in ipairs(lines) do
    local indent, name =
      line:match("^(%s*)readonly%s+property%s+QtObject%s+([%w_]+)%s*:%s*QtObject%s*{%s*$")
    if name then
      local object_id = "__omarchy_plugin_dev_" .. name
      result[#result + 1] = indent .. "readonly property alias " .. name .. ": " .. object_id
      result[#result + 1] = indent .. "QtObject {"
      result[#result + 1] = indent .. "  id: " .. object_id
      changed = true
    else
      result[#result + 1] = line
    end
  end
  return result, changed
end

local function populate_commons(shell_root, alias)
  local source_root = vim.fs.joinpath(shell_root, "Commons")
  local target_root = vim.fs.joinpath(alias, "Commons")
  if vim.fn.mkdir(target_root, "p") == -1 then
    return nil, "could not create QML tooling module at " .. target_root
  end

  for _, name in ipairs(entries(source_root)) do
    local source = vim.fs.joinpath(source_root, name)
    local target = vim.fs.joinpath(target_root, name)
    if name == "qmldir" then
      -- Keep relative type lookup inside the tooling overlay.
      if vim.fn.writefile(vim.fn.readfile(source), target) ~= 0 then
        return nil, "could not copy QML module definition to " .. target
      end
    elseif name:match("%.qml$") then
      local lines, changed = tooling_lines(source)
      if changed then
        if vim.fn.writefile(lines, target) ~= 0 then
          return nil, "could not write QML tooling type to " .. target
        end
      else
        local created, create_error = link(source, target)
        if not created then
          return nil, "could not link QML tooling type: " .. tostring(create_error)
        end
      end
    else
      local created, create_error = link(source, target)
      if not created then
        return nil, "could not link QML module file: " .. tostring(create_error)
      end
    end
  end
  return true
end

local function build_bridge(shell_root, alias)
  if not remove_path(alias) or vim.fn.mkdir(alias, "p") == -1 then
    return nil, "could not create QML import bridge at " .. alias
  end

  for _, name in ipairs(entries(shell_root)) do
    if name == "Commons" then
      local populated, populate_error = populate_commons(shell_root, alias)
      if not populated then
        return nil, populate_error
      end
    else
      local source = vim.fs.joinpath(shell_root, name)
      local target = vim.fs.joinpath(alias, name)
      local created, create_error = link(source, target)
      if not created then
        return nil, "could not create QML import bridge: " .. tostring(create_error)
      end
    end
  end
  return true
end

local function namespace_bridge(shell_root, cache_root)
  local canonical = vim.uv.fs_realpath(shell_root) or vim.fs.normalize(shell_root)
  local digest = vim.fn.sha256(canonical):sub(1, 12)
  local root = vim.fs.joinpath(
    cache_root or vim.fn.stdpath("cache"),
    "omarchy-plugin-dev",
    "qml-imports",
    digest
  )
  if vim.fn.mkdir(root, "p") == -1 then
    return nil, "could not create QML import cache at " .. root
  end

  local alias = vim.fs.joinpath(root, "qs")
  local marker = vim.fs.joinpath(root, ".source-signature")
  local signature = source_signature(canonical)
  local current = vim.fn.filereadable(marker) == 1 and vim.fn.readfile(marker)[1] or nil
  if current == signature and vim.fn.isdirectory(alias) == 1 then
    return root
  end

  local created, create_error = build_bridge(canonical, alias)
  if not created then
    remove_path(alias)
    return nil, create_error
  end
  if vim.fn.writefile({ signature }, marker) ~= 0 then
    remove_path(alias)
    return nil, "could not record QML import bridge state at " .. marker
  end
  return root
end

---@param opts? { cache_root?: string, qt_qml_queries?: string[][] }
---@return string[], string?
function M.import_paths(opts)
  opts = opts or {}
  local paths = {}
  local seen = {}
  local errors = {}
  local qt_path = qt_qml_import_path(opts.qt_qml_queries)
  if qt_path then
    add_unique(paths, seen, qt_path)
  end
  for _, configured in ipairs(require("omarchy_plugin_dev.config").get().qml_import_paths) do
    if is_quickshell_root(configured) then
      local bridge, bridge_error = namespace_bridge(configured, opts.cache_root)
      if bridge then
        add_unique(paths, seen, bridge)
      else
        errors[#errors + 1] = bridge_error
      end
    end
    add_unique(paths, seen, configured)
  end
  return paths, #errors > 0 and table.concat(errors, "; ") or nil
end

return M
