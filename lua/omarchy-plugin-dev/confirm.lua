local M = {}
local namespace = vim.api.nvim_create_namespace("omarchy-plugin-dev.confirm")
local selection = vim.api.nvim_create_namespace("omarchy-plugin-dev.confirm.selection")

local function wrap(text, width)
  local lines = {}
  while text ~= "" do
    local part = ""
    for _, char in ipairs(vim.fn.split(text, "\\zs")) do
      if part ~= "" and vim.fn.strdisplaywidth(part .. char) > width then
        break
      end
      part = part .. char
    end
    if #part < #text then
      part = part:match("^.*[%s/]") or part
    end
    lines[#lines + 1] = part
    text = text:sub(#part + 1)
  end
  return lines
end

local function content(context, width)
  local lines, highlights = { "" }, {}
  local text_hl = context.ready and "Normal" or "Comment"
  local status_hl = context.ready and "DiagnosticOk" or "DiagnosticWarn"
  local label_width = 0
  for _, field in ipairs(context.fields) do
    label_width = math.max(label_width, vim.fn.strdisplaywidth(field[1]))
  end
  local indent = string.rep(" ", math.min(label_width + 5, math.max(0, width - 10)))
  for _, field in ipairs(context.fields) do
    local label = "  " .. field[1] .. ":"
    local prefix = label .. string.rep(" ", math.max(1, #indent - #label))
    if #prefix >= width - 2 then
      for _, part in ipairs(wrap(label, width)) do
        lines[#lines + 1] = part
        highlights[#highlights + 1] = { #lines - 1, 0, #part, "Normal" }
      end
      prefix = indent
    else
      highlights[#highlights + 1] = { #lines, 0, #label, "Normal" }
    end
    for _, part in ipairs(wrap(field[2], math.max(1, width - #prefix - 2))) do
      lines[#lines + 1] = prefix .. part
      highlights[#highlights + 1] = {
        #lines - 1,
        #prefix,
        #lines[#lines],
        field.status and status_hl or text_hl,
      }
      prefix = indent
    end
  end
  vim.list_extend(lines, { "", "  Info:" })
  highlights[#highlights + 1] = { #lines - 1, 0, #lines[#lines], status_hl }
  for _, note in ipairs(context.info) do
    local prefix = "  - "
    for _, part in ipairs(wrap(note, math.max(1, width - 6))) do
      lines[#lines + 1] = prefix .. part
      highlights[#highlights + 1] = { #lines - 1, 0, #lines[#lines], text_hl }
      prefix = "    "
    end
  end
  vim.list_extend(lines, { "", "  [Y]es", "  [N]o" })
  highlights[#highlights + 1] = { #lines - 2, 2, #lines[#lines - 1], "DiagnosticOk" }
  highlights[#highlights + 1] = { #lines - 1, 2, #lines[#lines], "DiagnosticError" }
  return lines, highlights
end

function M.open(title, context, callback)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local width = math.max(1, math.min(100, vim.o.columns - 4))
  local lines, highlights = content(context, width)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, mark in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(
      buf,
      namespace,
      mark[1],
      mark[2],
      { end_col = mark[3], hl_group = mark[4] }
    )
  end
  vim.bo[buf].modifiable = false
  local height = math.max(1, math.min(#lines, vim.o.lines - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "single",
    title = { { " " .. title .. " ", "FloatTitle" } },
    title_pos = "center",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  })
  vim.wo[win].wrap = false
  local selected, answered = 1, false
  local function select(value)
    selected = value
    local line = #lines - 2 + selected
    vim.api.nvim_buf_clear_namespace(buf, selection, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, selection, line - 1, 0, { line_hl_group = "Visual" })
    vim.api.nvim_win_set_cursor(win, { line, 0 })
  end
  local function finish(yes)
    if answered then
      return
    end
    answered = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    callback(yes)
  end
  for _, key in ipairs({ "j", "k", "<Down>", "<Up>", "<Tab>", "<S-Tab>" }) do
    vim.keymap.set("n", key, function()
      select(3 - selected)
    end, { buffer = buf, silent = true })
  end
  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_win_get_cursor(win)[1]
    if line >= #lines - 1 then
      finish(line == #lines - 1)
    end
  end, { buffer = buf, silent = true })
  for _, key in ipairs({ "y", "Y" }) do
    vim.keymap.set("n", key, function()
      finish(true)
    end, { buffer = buf, silent = true })
  end
  for _, key in ipairs({ "n", "N", "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      finish(false)
    end, { buffer = buf, silent = true })
  end
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      local line = vim.api.nvim_win_get_cursor(win)[1]
      if line >= #lines - 1 then
        select(line - #lines + 2)
      else
        vim.api.nvim_buf_clear_namespace(buf, selection, 0, -1)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if not answered then
        answered = true
        callback(false)
      end
    end,
  })
  select(context.default_no and 2 or 1)
  return buf, win
end

return M
