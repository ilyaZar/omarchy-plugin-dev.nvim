local M = {}

local function add_unique(paths, seen, path)
  path = vim.fs.normalize(path)
  if not seen[path] then
    seen[path] = true
    paths[#paths + 1] = path
  end
end

local function is_quickshell_root(path)
  return vim.fn.filereadable(vim.fs.joinpath(path, "shell.qml")) == 1
    and vim.fn.isdirectory(vim.fs.joinpath(path, "Commons")) == 1
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
  if vim.uv.fs_realpath(alias) == canonical then
    return root
  end
  if vim.uv.fs_lstat(alias) then
    return nil, "QML import cache path is occupied: " .. alias
  end

  local created, create_error = vim.uv.fs_symlink(canonical, alias, { dir = true })
  if not created then
    return nil, "could not create QML import bridge: " .. tostring(create_error)
  end
  return root
end

---@param opts? { cache_root?: string }
---@return string[], string?
function M.import_paths(opts)
  opts = opts or {}
  local paths = {}
  local seen = {}
  local errors = {}
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
