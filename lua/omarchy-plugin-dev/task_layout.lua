local M = {}

local function list_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "OverseerList" then
      return win
    end
  end
end

local function sibling(layout, win)
  if layout[1] == "leaf" then
    return nil
  end
  local children = layout[2]
  if layout[1] == "row" and #children == 2 then
    for index, child in ipairs(children) do
      local other = children[3 - index]
      if child[1] == "leaf" and child[2] == win and other[1] == "leaf" then
        return other[2]
      end
    end
  end
  for _, child in ipairs(children) do
    local found = sibling(child, win)
    if found then
      return found
    end
  end
end

local function editor_height()
  local height = vim.o.lines - vim.o.cmdheight
  if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1) then
    height = height - 1
  end
  if
    vim.o.laststatus >= 2 or (vim.o.laststatus == 1 and #vim.api.nvim_tabpage_list_wins(0) > 1)
  then
    height = height - 1
  end
  return height
end

local function size(total, fraction, minimum, maximum)
  maximum = math.max(1, maximum)
  minimum = math.min(minimum, maximum)
  return math.max(minimum, math.min(maximum, math.floor(total * fraction + 0.5)))
end

function M.open(backend, opts)
  local layout = require("omarchy-plugin-dev.config").get().task_layout
  if not layout or list_window() then
    return backend.open(opts)
  end

  local tab = vim.api.nvim_get_current_tabpage()
  local existing = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    existing[win] = true
  end
  backend.open(vim.tbl_extend("force", opts, { direction = "bottom" }))
  if vim.api.nvim_get_current_tabpage() ~= tab then
    return
  end
  local win = list_window()
  if not win or existing[win] then
    return
  end
  local output = sibling(vim.fn.winlayout(), win)
  -- Resize only the two new panes, never an unrelated editor split.
  if not output or existing[output] then
    return
  end

  local height = editor_height()
  local width = vim.api.nvim_win_get_width(win) + vim.api.nvim_win_get_width(output)
  vim.api.nvim_win_set_height(
    win,
    size(
      height,
      layout.height,
      math.max(3, vim.o.winminheight),
      height - math.max(1, vim.o.winminheight) - 1
    )
  )
  vim.api.nvim_win_set_width(
    win,
    size(
      width,
      layout.list_width,
      math.max(10, vim.o.winminwidth),
      width - math.max(10, vim.o.winminwidth)
    )
  )
end

return M
