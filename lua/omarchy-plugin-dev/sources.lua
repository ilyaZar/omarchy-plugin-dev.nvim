local M = {}
local targets = require("omarchy-plugin-dev.targets")
local messages = require("omarchy-plugin-dev.messages")
local running = {}

function M.snapshot(info)
  local requests, err = targets.requests(info.root)
  if not requests then
    return { entries = {}, error = err, detail = err }
  end
  local selected = targets.selected(info.root)
  local entries, context, selected_error = {}, nil, nil
  local native = vim.fs.joinpath(vim.env.HOME, ".config", "omarchy", "plugins", info.manifest.id)
  for _, request in ipairs(requests) do
    local entry = request.entry
    if entry.name == selected then
      local report, inspect_error = targets.inspect(request)
      if report then
        context, selected_error = targets.context(request, report)
      else
        selected_error = inspect_error
      end
    end
    local installed = context
      and entry.name == selected
      and vim.uv.fs_realpath(native) == context.root
    entries[#entries + 1] = {
      name = entry.name,
      label = entry.name,
      active = entry.name == selected and context ~= nil and installed or false,
      detail = entry.type .. "  " .. request.display,
    }
  end
  if selected and not context and not selected_error then
    selected_error = "Selected target no longer exists; choose a build target"
  end
  return {
    entries = entries,
    context = context,
    error = selected_error,
    detail = selected_error or (selected and ("Selected: " .. selected) or "Choose a build target"),
  }
end

local function confirmation(request, report)
  local entry = request.entry
  local destructive = report.operation == "replace" and report.kind == "git-clone"
  local fields = {
    { "Plugin", request.id },
    { "Name", entry.name },
    { "Type", entry.type },
    { "Source", entry.source },
    { "Destination", entry.destination },
    { "Current", report.kind .. " (" .. report.operation .. ")", status = true },
  }
  if report.revision ~= "" then
    fields[#fields + 1] = { "Current revision", report.revision }
    fields[#fields + 1] = { "Current branch", report.branch }
  end
  if entry.ref then
    local kind, value = next(entry.ref)
    fields[#fields + 1] = { kind, value }
  end
  local notes = {}
  if report.operation == "reuse" then
    notes[#notes + 1] = "Reuse this destination. No files, links, or checkouts will be changed."
  elseif destructive then
    notes[#notes + 1] = string.format(
      "%d modified files, %d untracked files, %d ignored files.",
      report.modified,
      report.untracked,
      report.ignored
    )
    notes[#notes + 1] = "Commits ahead: "
      .. report.ahead
      .. "; comparison: "
      .. report.comparison
      .. " (local information, possibly stale)."
    notes[#notes + 1] =
      "Permanently delete this directory and its Git history. No backup or rollback."
  elseif report.kind == "symlink" then
    notes[#notes + 1] = "Replace only the symlink, never its target folder."
  else
    notes[#notes + 1] = "Prepare this destination once. Build commands will not clone or relink it."
  end
  if entry.type == "git-clone" or entry.type == "symlink" then
    notes[#notes + 1] =
      "Omarchy updates may change this checkout, including a linked source or tagged clone."
  end
  notes[#notes + 1] = "Preserve plugin settings and enabled state. Only use sources you trust."
  return {
    fields = fields,
    info = notes,
    ready = report.operation == "reuse",
    default_no = destructive,
  }
end

local function prepare(request, report, done)
  request.expected = report
  request.delete_approved = report.operation == "replace" and report.kind == "git-clone"
  local function finish(result)
    local output =
      vim.trim(((result.stdout or "") .. (result.stderr or "")):gsub("\27%[[%d;]*m", ""))
    if result.code == 0 then
      local current, err = targets.request(request.project, request.entry.name)
      local report, context
      if current and current.config_hash == request.config_hash then
        report, err = targets.inspect(current)
        if report then
          context, err = targets.context(current, report)
        end
      else
        err = err or "Configuration changed during preparation; select again"
      end
      local saved
      if context then
        saved, err = targets.remember(request.project, request.entry.name)
      end
      if not saved then
        output = output .. "\nCould not remember selection: " .. tostring(err)
        result.code = 1
      end
    else
      output = "Target preparation failed (exit " .. result.code .. ")\n" .. output
    end
    running[request.id] = nil
    messages.show(output, result.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
    done()
  end
  if report.operation ~= "reuse" then
    messages.show("Preparing " .. request.entry.name .. "...", vim.log.levels.INFO)
  end
  local ok, err = pcall(
    vim.system,
    { targets.script("prepare-target"), "prepare", vim.json.encode(request) },
    {
      text = true,
      timeout = 180000,
      env = targets.environment(),
    },
    vim.schedule_wrap(finish)
  )
  if not ok then
    finish({ code = 1, stderr = tostring(err) })
  end
end

function M.choose(info, name, done, active)
  done = done or function() end
  if running[info.manifest.id] then
    return
  end
  local request, err = targets.request(info.root, name)
  if not request then
    messages.show(err, vim.log.levels.ERROR)
    done()
    return
  end
  running[request.id] = true
  local function finish(result)
    if active and not active() then
      running[request.id] = nil
      return
    end
    if result.code ~= 0 then
      running[request.id] = nil
      local detail = vim.trim(result.stderr or "")
      messages.show(
        detail ~= "" and detail or ("Target inspection failed (exit " .. result.code .. ")"),
        vim.log.levels.ERROR
      )
      done()
      return
    end
    local ok, report = pcall(vim.json.decode, result.stdout or "")
    if not ok or type(report) ~= "table" then
      running[request.id] = nil
      messages.show("Invalid target inspection result", vim.log.levels.ERROR)
      done()
      return
    end
    if report.operation == "reuse" then
      local context, validation_error = targets.context(request, report)
      if not context then
        running[request.id] = nil
        messages.show(validation_error, vim.log.levels.ERROR)
        done()
        return
      end
    end
    require("omarchy-plugin-dev.confirm").open(
      "Select build target?",
      confirmation(request, report),
      function(yes)
        if yes and (not active or active()) then
          prepare(request, report, done)
        else
          running[request.id] = nil
        end
      end
    )
  end
  local ok, spawn_error = pcall(
    vim.system,
    { targets.script("prepare-target"), "inspect", vim.json.encode(request) },
    {
      text = true,
      timeout = 10000,
      env = targets.environment(),
    },
    vim.schedule_wrap(finish)
  )
  if not ok then
    finish({ code = 1, stderr = tostring(spawn_error) })
  end
end

return M
