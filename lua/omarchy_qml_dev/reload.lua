local M = {}

local function executable(command)
  return type(command) == "string" and command ~= "" and vim.fn.executable(command) == 1
end

function M.parse_ipc_show(output, endpoint)
  local active_target = nil
  for line in (output or ""):gmatch("[^\r\n]+") do
    local target = line:match("^target%s+(.+)$")
    if target then
      active_target = target
    elseif active_target == endpoint.target then
      local method = line:match("^%s+function%s+([%w_]+)%(")
      if method == endpoint.method then
        return true
      end
    end
  end
  return false
end

local function inspect_ipc(config)
  local command = config.executables.quickshell
  if not executable(command) then
    return nil, string.format("%s is not executable", command)
  end

  local result = vim
    .system({
      command,
      "ipc",
      "-n",
      "-p",
      config.restart.shell_path,
      "show",
    }, { text = true })
    :wait(2500)
  if result.code ~= 0 then
    return nil, "the running shell IPC surface could not be inspected"
  end
  return result.stdout or ""
end

local function supports_generation_reload(config)
  local path = vim.fs.joinpath(config.restart.shell_path, "shell.qml")
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return false
  end
  local count = 0
  for _, line in ipairs(lines) do
    if line:find("Quickshell.reload(false)", 1, true) then
      count = count + 1
    end
  end
  return count >= 2
end

function M.capability(opts)
  opts = opts or {}
  local config = opts.config or require("omarchy_qml_dev.config").get()
  local endpoint = config.restart.soft_reload
  local output = opts.ipc_output
  local inspect_error
  if output == nil then
    output, inspect_error = inspect_ipc(config)
  end

  local endpoint_available = output ~= nil and M.parse_ipc_show(output, endpoint)
  local generation_reload = opts.generation_reload
  if generation_reload == nil then
    generation_reload = opts.ipc_output ~= nil or supports_generation_reload(config)
  end
  local soft_available = endpoint_available and generation_reload
  local soft_command_available = executable(config.executables.omarchy_shell)
  local restart_available = executable(config.executables.omarchy)
  local mode = config.restart.mode

  if mode ~= "restart" and soft_available and soft_command_available then
    local command = {
      config.executables.omarchy_shell,
      endpoint.target,
      endpoint.method,
    }
    vim.list_extend(command, endpoint.args or {})
    return {
      available = true,
      kind = "soft",
      label = "Soft reload",
      command = command,
      detail = string.format("verified IPC endpoint %s.%s", endpoint.target, endpoint.method),
    }
  end

  if mode == "soft" then
    return {
      available = false,
      kind = "soft",
      label = "Soft reload unavailable",
      detail = inspect_error
        or (endpoint_available and "the running Omarchy rescan can retain stale IPC handlers")
        or string.format("IPC endpoint %s.%s is not exposed", endpoint.target, endpoint.method),
    }
  end

  return {
    available = restart_available,
    kind = "restart",
    label = "Restart shell",
    command = { config.executables.omarchy, "restart", "shell" },
    detail = soft_available and "full restart selected by configuration"
      or (endpoint_available and "safe replacement requires a full shell restart")
      or "no verified soft-reload IPC endpoint; uses a full shell restart",
  }
end

return M
