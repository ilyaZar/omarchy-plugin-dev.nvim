local M = {}

local required_fields = {
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

function M.decode(text, source_path)
  local ok, manifest = pcall(vim.json.decode, text)
  if not ok then
    return nil, string.format("manifest.json is not valid JSON at %s: %s", source_path, manifest)
  end
  if not is_object(manifest) then
    return nil, string.format("manifest.json must contain an object at %s", source_path)
  end
  return manifest
end

function M.validate(manifest, root)
  if not is_object(manifest) then
    return nil, "manifest must be an object"
  end
  if manifest.schemaVersion ~= 1 then
    return nil, "manifest schemaVersion must be the number 1"
  end
  for _, field in ipairs(required_fields) do
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
  local manifest, decode_error = M.decode(text, path)
  if not manifest then
    return nil, decode_error
  end
  local valid, validation_error = M.validate(manifest, root)
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

return M
