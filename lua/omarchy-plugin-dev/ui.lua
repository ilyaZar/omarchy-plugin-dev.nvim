local M = {}

local dashboard = require("omarchy-plugin-dev.dashboard")
local dashboard_win
local namespace = vim.api.nvim_create_namespace("omarchy-plugin-dev.dashboard")
local selection_namespace = vim.api.nvim_create_namespace("omarchy-plugin-dev.dashboard.selection")

local function draw_row(bufnr, line, chunks)
  local parts = {}
  for _, chunk in ipairs(chunks) do
    parts[#parts + 1] = chunk[1]
  end
  vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, { table.concat(parts) })
  local col = 0
  for _, chunk in ipairs(chunks) do
    local next_col = col + #chunk[1]
    if next_col > col then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, line - 1, col, {
        end_col = next_col,
        hl_group = chunk[2] or "Normal",
      })
    end
    col = next_col
  end
end

local function attach_selection(buf, win, activate)
  local items, selected = {}, 1
  local moving = false
  local function select(index)
    selected = math.max(1, math.min(#items, index))
    local item = items[selected]
    if not item then
      return
    end
    moving = true
    vim.api.nvim_win_set_cursor(win, { item.line, 0 })
    moving = false
    vim.api.nvim_buf_clear_namespace(buf, selection_namespace, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, selection_namespace, item.line - 1, 0, {
      line_hl_group = "Visual",
    })
  end
  local function map(keys, callback)
    for _, key in ipairs(keys) do
      vim.keymap.set("n", key, callback, { buffer = buf, silent = true })
    end
  end
  map({ "j", "<Down>" }, function()
    select(selected + vim.v.count1)
  end)
  map({ "k", "<Up>" }, function()
    select(selected - vim.v.count1)
  end)
  map({ "gg" }, function()
    select(1)
  end)
  map({ "G" }, function()
    select(#items)
  end)
  map({ "<CR>" }, function()
    local item = items[selected]
    if item and item.action then
      activate(item.action)
    end
  end)
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if moving or not vim.api.nvim_win_is_valid(win) then
        return
      end
      local line = vim.api.nvim_win_get_cursor(win)[1]
      local nearest, distance = 1, math.huge
      for index, item in ipairs(items) do
        local gap = math.abs(line - item.line)
        if gap < distance then
          nearest, distance = index, gap
        end
      end
      select(nearest)
    end,
  })
  return function(rows, reset)
    items = {}
    for line, row in ipairs(rows) do
      if row.action or row.selectable then
        items[#items + 1] = { line = line + 2, action = row.action }
      end
    end
    select(reset and 1 or selected)
  end
end

local function render(state, reset)
  state.views = dashboard.rows(state.snapshot, state.width)
  local tabs = {}
  for index, name in ipairs(dashboard.tabs) do
    tabs[#tabs + 1] = {
      string.format("  [%d]", index),
      state.active_view == index and "DiagnosticWarn" or "DiagnosticInfo",
    }
    tabs[#tabs + 1] = { " " .. name, "Normal" }
  end
  local rows = { tabs, {} }
  vim.list_extend(rows, state.views[state.active_view])
  rows[#rows + 1] = {}
  local view = state.win and vim.api.nvim_win_call(state.win, vim.fn.winsaveview)
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
  vim.api.nvim_buf_set_lines(
    state.buf,
    0,
    -1,
    false,
    vim.tbl_map(function()
      return ""
    end, rows)
  )
  for line, chunks in ipairs(rows) do
    draw_row(state.buf, line, chunks)
  end
  vim.bo[state.buf].modifiable = false
  if state.select then
    state.select(state.views[state.active_view], reset)
    vim.api.nvim_win_call(state.win, function()
      vim.fn.winrestview(reset and { topline = 1 } or view)
    end)
  end
end

local function close(state)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  elseif vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
end

local function refresh(state)
  state.snapshot = nil
  local snapshot, inspection_error = dashboard.collect(state.source_buf)
  if not snapshot then
    require("omarchy-plugin-dev.messages").show(
      "Cannot " .. (state.win and "refresh" or "open") .. " dashboard: " .. inspection_error,
      vim.log.levels.WARN
    )
    close(state)
    return false
  end
  state.snapshot = snapshot
  render(state)
  if not snapshot.build_root then
    return true
  end
  require("omarchy-plugin-dev.project").external_validate_async(
    snapshot.build_root,
    function(valid, detail)
      if
        state.snapshot ~= snapshot
        or not vim.api.nvim_buf_is_valid(state.buf)
        or (state.win and not vim.api.nvim_win_is_valid(state.win))
      then
        return
      end
      snapshot.validation = {
        state = valid and "passed" or "failed",
        detail = detail and detail:gsub("\n", " | "),
      }
      render(state)
    end
  )
  return true
end

local function open(state)
  local height = 0
  for _, rows in ipairs(state.views) do
    height = math.max(height, #rows)
  end
  height = math.max(1, math.min(height + 3, vim.o.lines - 4))
  local win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    border = "single",
    title = { { " Omarchy Plugin Dev ", "FloatTitle" } },
    title_pos = "center",
    footer = {
      { " [j/k]", "DiagnosticOk" },
      { " move  ", "Comment" },
      { "[Tab]", "DiagnosticOk" },
      { " switch  ", "Comment" },
      { "[r]", "DiagnosticOk" },
      { "efresh  ", "Comment" },
      { "[q/Esc]", "DiagnosticOk" },
      { " close ", "Comment" },
    },
    footer_pos = "center",
    width = state.width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - state.width) / 2)),
    style = "minimal",
  })
  -- Keep full paths and failure details accessible rather than truncating them.
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].cursorline = false
  return win
end

local function bind_keys(state)
  local function map(lhs, callback, desc)
    vim.keymap.set("n", lhs, callback, {
      buffer = state.buf,
      desc = "Omarchy Plugin: " .. desc,
      silent = true,
    })
  end
  local function activate(method)
    if type(method) == "table" then
      local snapshot = state.snapshot
      require("omarchy-plugin-dev.sources").choose(snapshot.info, method.target, function()
        if vim.api.nvim_win_is_valid(state.win) then
          refresh(state)
        end
      end, function()
        return vim.api.nvim_win_is_valid(state.win) and state.snapshot == snapshot
      end)
      return
    end
    close(state)
    require("omarchy-plugin-dev.actions")[method](state.source_buf)
  end
  state.select = attach_selection(state.buf, state.win, activate)
  state.select(state.views[state.active_view], true)
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    map(lhs, function()
      close(state)
    end, "close dashboard")
  end
  map("r", function()
    refresh(state)
  end, "refresh dashboard")
  local function switch(index)
    state.active_view = (index - 1) % #dashboard.tabs + 1
    render(state, true)
  end
  map("<Tab>", function()
    switch(state.active_view + 1)
  end, "next dashboard tab")
  map("<S-Tab>", function()
    switch(state.active_view - 1)
  end, "previous dashboard tab")
  for index in ipairs(dashboard.tabs) do
    map(tostring(index), function()
      switch(index)
    end, "switch dashboard tab")
  end
  for _, item in ipairs(dashboard.actions) do
    map(item[1], function()
      activate(item[3])
    end, item[2])
  end
end

function M.dashboard(bufnr)
  local state = {
    source_buf = bufnr and bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf(),
    width = math.max(1, math.min(100, math.floor(vim.o.columns * 0.84), vim.o.columns - 4)),
    active_view = 1,
    buf = vim.api.nvim_create_buf(false, true),
  }
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "omarchy-plugin-dev"
  if not refresh(state) then
    return
  end
  if dashboard_win and vim.api.nvim_win_is_valid(dashboard_win) then
    vim.api.nvim_win_close(dashboard_win, true)
  end
  state.win = open(state)
  dashboard_win = state.win
  bind_keys(state)
  return state.buf, state.win
end

return M
