local config = require("omarchy-plugin-dev.config")
local layout = require("omarchy-plugin-dev.task_layout")
local saved_config = vim.deepcopy(config.get())
local defaults = config.setup().task_layout
assert(
  defaults and defaults.height == 1 / 3 and defaults.list_width == 1 / 2,
  "shipped task layout must use one-third height and equal pane widths"
)
assert(vim.deep_equal(config.setup({ task_layout = {} }).task_layout, defaults))
local partial = { height = 0.15 }
local configured = config.setup({ task_layout = partial }).task_layout
assert(configured and configured.list_width == 0.5)
assert(partial.list_width == nil, "setup mutated caller-owned layout options")
local active = config.get()
for _, invalid in ipairs({
  true,
  "bottom",
  { height = 0 },
  { height = 1 },
  { height = -0.5 },
  { height = math.huge },
  { height = 0 / 0 },
  { list_width = 1 },
  { list_width = false },
  { list_width = "0.5" },
}) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  local ok, err = pcall(config.setup, { task_layout = invalid })
  assert(not ok and tostring(err):find("task_layout", 1, true), "invalid task layout was accepted")
  assert(config.get() == active, "invalid layout replaced active configuration")
end

local original_tab = vim.api.nvim_get_current_tabpage()
local options = {}
for _, name in ipairs({
  "lines",
  "columns",
  "showtabline",
  "laststatus",
  "cmdheight",
  "winminheight",
  "winminwidth",
  "winheight",
  "winwidth",
}) do
  options[name] = vim.o[name]
end
vim.o.lines = 52
vim.o.columns = 101
vim.o.showtabline = 0
vim.o.laststatus = 2
vim.o.cmdheight = 1
vim.o.winminheight = 1
vim.o.winminwidth = 1
vim.o.winheight = 1
vim.o.winwidth = 1
vim.cmd.tabnew()
local source = vim.api.nvim_get_current_win()
local list, output, received
local backend = {
  open = function(opts)
    received = opts
    if not list or not vim.api.nvim_win_is_valid(list) then
      local current = vim.api.nvim_get_current_win()
      vim.cmd("noautocmd botright new")
      list = vim.api.nvim_get_current_win()
      vim.bo.buftype = "nofile"
      vim.bo.bufhidden = "wipe"
      vim.bo.filetype = "OverseerList"
      vim.cmd("noautocmd rightbelow vnew")
      output = vim.api.nvim_get_current_win()
      vim.bo.buftype = "nofile"
      vim.bo.bufhidden = "wipe"
      vim.api.nvim_win_set_height(list, 5)
      vim.api.nvim_win_set_width(list, 20)
      vim.api.nvim_set_current_win(current)
    end
    if opts.enter then
      vim.api.nvim_set_current_win(list)
    end
  end,
}
local function close_panel()
  vim.api.nvim_win_close(output, true)
  vim.api.nvim_win_close(list, true)
end
local opts = { enter = false, focus_task_id = 42 }
config.setup({ task_layout = false })
layout.open(backend, opts)
assert(received == opts, "disabled layout modified Overseer open options")
assert(vim.api.nvim_win_get_height(list) == 5 and vim.api.nvim_win_get_width(list) == 20)
close_panel()

config.setup({ task_layout = {} })
layout.open(backend, opts)
assert(received.direction == "bottom" and received.focus_task_id == 42 and received.enter == false)
assert(opts.direction == nil, "layout mutated caller-owned open options")
assert(vim.api.nvim_get_current_win() == source, "layout stole focus")
assert(vim.api.nvim_win_get_height(list) == 17, "one-third height was not rounded")
assert(vim.api.nvim_win_get_width(list) == 50, "task list was not half the panel width")
assert(vim.api.nvim_win_get_width(output) == 50)
vim.api.nvim_win_set_height(list, 11)
vim.api.nvim_win_set_width(list, 30)
layout.open(backend, opts)
assert(
  vim.api.nvim_win_get_height(list) == 11 and vim.api.nvim_win_get_width(list) == 30,
  "opening an existing panel reset manual dimensions"
)
config.setup({ task_layout = { height = 0.15, list_width = 0.3 } })
layout.open(backend, opts)
assert(vim.api.nvim_win_get_height(list) == 11, "configuration change resized an open panel")
close_panel()
layout.open(backend, { enter = true })
assert(vim.api.nvim_get_current_win() == list, "layout ignored requested focus")
assert(vim.api.nvim_win_get_height(list) == 8, "15 percent of 50 rows should round to 8")
assert(vim.api.nvim_win_get_width(list) == 30, "custom width fraction was ignored")
close_panel()

for _, fraction in ipairs({ 0.001, 0.999 }) do
  vim.o.lines = 12
  vim.o.columns = 25
  config.setup({ task_layout = { height = fraction, list_width = fraction } })
  layout.open(backend, opts)
  assert(vim.api.nvim_win_get_height(list) >= 3, "tiny fraction made the panel unusable")
  assert(vim.api.nvim_win_get_height(source) >= 1, "panel consumed the whole editor")
  assert(
    vim.api.nvim_win_get_width(list) >= 10 and vim.api.nvim_win_get_width(output) >= 10,
    "width fraction left an unusable pane"
  )
  close_panel()
end

vim.o.lines = 52
vim.o.columns = 101
local untouched
layout.open({
  open = function()
    vim.cmd("noautocmd rightbelow vnew")
    list = vim.api.nvim_get_current_win()
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.filetype = "OverseerList"
    untouched = { vim.api.nvim_win_get_width(list), vim.api.nvim_win_get_height(list) }
  end,
}, opts)
assert(
  vim.api.nvim_win_get_width(list) == untouched[1]
    and vim.api.nvim_win_get_height(list) == untouched[2],
  "layout resized an unrelated sibling"
)
vim.api.nvim_win_close(list, true)
vim.cmd.tabclose()
vim.api.nvim_set_current_tabpage(original_tab)
for name, value in pairs(options) do
  vim.o[name] = value
end
---@diagnostic disable-next-line: param-type-mismatch
config.setup(saved_config)
