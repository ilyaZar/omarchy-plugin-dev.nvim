local M = {}

local version_cache = {}

local function output(result)
  local parts = {}
  for _, value in ipairs({ result.stdout, result.stderr }) do
    value = vim.trim(value or "")
    if value ~= "" then
      parts[#parts + 1] = value
    end
  end
  return table.concat(parts, "\n")
end

local function executable_path(candidate)
  if vim.fn.executable(candidate) ~= 1 then
    return nil
  end
  local resolved = vim.fn.exepath(candidate)
  return resolved ~= "" and resolved or candidate
end

local function version(path)
  if version_cache[path] then
    return version_cache[path]
  end

  local result = vim.system({ path, "--version" }, { text = true }):wait(2000)
  local detail = output(result)
  local number
  if result.code == 0 then
    number = detail:match("[Qq][Mm][Ll][Ll][Ii][Nn][Tt]%s+(%d+[%d.]*)")
      or detail:match("(%d+[%d.]*)")
  end
  local info = {
    code = result.code,
    number = number,
    major = number and tonumber(number:match("^(%d+)")) or nil,
    output = detail,
  }
  version_cache[path] = info
  return info
end

local function auto_candidates()
  return {
    "/usr/lib/qt6/bin/qmllint",
    "qmllint",
  }
end

function M.resolve()
  local configured = require("omarchy_plugin_dev.config").get().executables.qmllint
  if configured ~= "auto" then
    local path = executable_path(configured)
    if not path then
      return nil, string.format("configured qmllint is not executable: %s", configured)
    end
    local info = version(path)
    return {
      path = path,
      version = info.number,
      major = info.major,
      explicit = true,
    }
  end

  local incompatible = {}
  local seen = {}
  for _, candidate in ipairs(auto_candidates()) do
    local path = executable_path(candidate)
    if path and not seen[path] then
      seen[path] = true
      local info = version(path)
      if info.code == 0 and info.major and info.major >= 6 then
        return {
          path = path,
          version = info.number,
          major = info.major,
          explicit = false,
        }
      end
      incompatible[#incompatible + 1] = string.format(
        "%s (%s)",
        path,
        info.number and "version " .. info.number or "unknown version"
      )
    end
  end

  local message = "Qt 6 qmllint is missing; install qt6-declarative"
  if #incompatible > 0 then
    message = message .. "; incompatible candidate: " .. table.concat(incompatible, ", ")
  end
  return nil, message
end

function M.executable()
  local info = M.resolve()
  return info and info.path or nil
end

function M.available()
  return M.executable() ~= nil
end

function M.status()
  local info, resolve_error = M.resolve()
  if not info then
    return "missing", resolve_error
  end
  local detail = info.path
  if info.version then
    detail = detail .. " (version " .. info.version .. ")"
  else
    detail = detail .. " (version unknown)"
  end
  if info.explicit and info.major and info.major < 6 then
    detail = detail .. " - explicit non-Qt-6 override"
  end
  return "available", detail, info
end

return M
