local M = {}

local defaults = {
  executables = {
    journalctl = "journalctl",
    omarchy = "omarchy",
    omarchy_shell = "omarchy-shell",
    qml_language_server = "auto",
    qmllint = "qmllint",
    quickshell = "qs",
  },
  logs = {
    follow = true,
    match = "_COMM=quickshell",
  },
  mappings = {
    enabled = true,
    hot_reload = "<C-b>",
    rebuild = "<C-S-b>",
    test = "<localleader>t",
    menu = "<localleader>o",
  },
  notify = true,
  log_level = vim.log.levels.INFO,
  qml_import_paths = { "/usr/share/omarchy/shell" },
  restart = {
    mode = "auto",
    shell_path = vim.fs.joinpath(vim.env.OMARCHY_PATH or "/usr/share/omarchy", "shell"),
    soft_reload = {
      target = "shell",
      method = "rescanPlugins",
      args = {},
    },
  },
  tasks = {},
}

local values = vim.deepcopy(defaults)

local function validate(opts)
  if not vim.tbl_contains({ "auto", "restart", "soft" }, opts.restart.mode) then
    error("omarchy-plugin-dev.nvim: restart.mode must be auto, restart, or soft")
  end

  if opts.mappings ~= false and type(opts.mappings) ~= "table" then
    error("omarchy-plugin-dev.nvim: mappings must be a table or false")
  end
end

function M.setup(opts)
  values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  validate(values)
  return values
end

function M.get()
  return values
end

function M.defaults()
  return vim.deepcopy(defaults)
end

return M
