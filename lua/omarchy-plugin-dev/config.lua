local M = {}

---@class OmarchyPluginDevExecutables
---@field journalctl string
---@field jq string
---@field omarchy string
---@field qml_language_server string
---@field qmllint string
---@field rsync string

---@class OmarchyPluginDevMappings
---@field enabled boolean
---@field hot_reload string|false
---@field build string|false
---@field test string|false
---@field menu string|false

---@class OmarchyPluginDevOptions
---@field config_file? string
---@field diagnostics? false|table
---@field enable_auto? boolean
---@field enable_first_install? boolean
---@field executables? table<string, string>
---@field format_on_save? boolean
---@field logs? { follow?: boolean, match?: string }
---@field mappings? false|table<string, boolean|string>
---@field notify? boolean
---@field log_level? integer
---@field qml_file_filter? fun(context: OmarchyPluginDevQmlFileContext): boolean
---@field qml_import_paths? string[]
---@field task_layout? false|{ height?: number, list_width?: number }
---@field tasks? table<string, table|fun(context: table): table?>

---@class OmarchyPluginDevQmlFileContext
---@field manifest table
---@field path string
---@field relative_path string
---@field root string

---@class OmarchyPluginDevConfig
---@field config_file? string
---@field diagnostics false|table
---@field enable_auto boolean
---@field enable_first_install boolean
---@field executables OmarchyPluginDevExecutables
---@field format_on_save boolean
---@field logs { follow: boolean, match: string }
---@field mappings false|OmarchyPluginDevMappings
---@field notify boolean
---@field log_level integer
---@field qml_file_filter? fun(context: OmarchyPluginDevQmlFileContext): boolean
---@field qml_import_paths string[]
---@field task_layout false|{ height: number, list_width: number }
---@field tasks table<string, table|fun(context: table): table?>

---@type OmarchyPluginDevConfig
local defaults = {
  diagnostics = {
    virtual_text = false,
  },
  enable_auto = true,
  enable_first_install = true,
  executables = {
    journalctl = "journalctl",
    jq = "jq",
    omarchy = "omarchy",
    qml_language_server = "auto",
    qmllint = "auto",
    rsync = "rsync",
  },
  format_on_save = true,
  logs = {
    follow = true,
    match = "_COMM=quickshell",
  },
  mappings = {
    enabled = true,
    hot_reload = "<C-b>",
    build = "<C-S-b>",
    test = "<localleader>t",
    menu = "<localleader>o",
  },
  notify = true,
  log_level = vim.log.levels.INFO,
  qml_import_paths = { "/usr/share/omarchy/shell" },
  task_layout = {
    height = 1 / 3,
    list_width = 1 / 2,
  },
  tasks = {},
}

---@type OmarchyPluginDevConfig
local values = vim.deepcopy(defaults)

local function validate(opts)
  if opts.config_file ~= nil and (type(opts.config_file) ~= "string" or opts.config_file == "") then
    error("omarchy-plugin-dev.nvim: config_file must be a non-empty path")
  end
  if opts.diagnostics ~= false and type(opts.diagnostics) ~= "table" then
    error("omarchy-plugin-dev.nvim: diagnostics must be a table or false")
  end
  if type(opts.enable_auto) ~= "boolean" then
    error("omarchy-plugin-dev.nvim: enable_auto must be a boolean")
  end
  if type(opts.enable_first_install) ~= "boolean" then
    error("omarchy-plugin-dev.nvim: enable_first_install must be a boolean")
  end
  if type(opts.format_on_save) ~= "boolean" then
    error("omarchy-plugin-dev.nvim: format_on_save must be a boolean")
  end
  if type(opts.logs) ~= "table" then
    error("omarchy-plugin-dev.nvim: logs must be a table")
  end
  if type(opts.logs.follow) ~= "boolean" then
    error("omarchy-plugin-dev.nvim: logs.follow must be a boolean")
  end
  if type(opts.logs.match) ~= "string" or opts.logs.match == "" then
    error("omarchy-plugin-dev.nvim: logs.match must be a non-empty string")
  end
  if opts.mappings ~= false and type(opts.mappings) ~= "table" then
    error("omarchy-plugin-dev.nvim: mappings must be a table or false")
  end
  if opts.mappings ~= false then
    if type(opts.mappings.enabled) ~= "boolean" then
      error("omarchy-plugin-dev.nvim: mappings.enabled must be a boolean")
    end
    for _, name in ipairs({ "hot_reload", "build", "test", "menu" }) do
      local lhs = opts.mappings[name]
      if lhs ~= false and (type(lhs) ~= "string" or lhs == "") then
        error(string.format("omarchy-plugin-dev.nvim: mappings.%s must be a key or false", name))
      end
    end
  end
  if type(opts.notify) ~= "boolean" then
    error("omarchy-plugin-dev.nvim: notify must be a boolean")
  end
  if type(opts.log_level) ~= "number" or opts.log_level % 1 ~= 0 then
    error("omarchy-plugin-dev.nvim: log_level must be an integer")
  end
  if type(opts.executables) ~= "table" then
    error("omarchy-plugin-dev.nvim: executables must be a table")
  end
  for name, executable in pairs(opts.executables) do
    if type(executable) ~= "string" or executable == "" then
      error(string.format("omarchy-plugin-dev.nvim: executables.%s must be a string", name))
    end
  end
  if opts.qml_file_filter ~= nil and type(opts.qml_file_filter) ~= "function" then
    error("omarchy-plugin-dev.nvim: qml_file_filter must be a function")
  end
  if type(opts.qml_import_paths) ~= "table" or not vim.islist(opts.qml_import_paths) then
    error("omarchy-plugin-dev.nvim: qml_import_paths must be an array")
  end
  for index, import_path in ipairs(opts.qml_import_paths) do
    if type(import_path) ~= "string" or import_path == "" then
      error(string.format("omarchy-plugin-dev.nvim: qml_import_paths[%d] must be a string", index))
    end
  end
  if opts.task_layout ~= false then
    if type(opts.task_layout) ~= "table" then
      error("omarchy-plugin-dev.nvim: task_layout must be a table or false")
    end
    for _, name in ipairs({ "height", "list_width" }) do
      local value = opts.task_layout[name]
      if type(value) ~= "number" or not (value > 0 and value < 1) then
        error("omarchy-plugin-dev.nvim: task_layout." .. name .. " must be between 0 and 1")
      end
    end
  end
  if type(opts.tasks) ~= "table" then
    error("omarchy-plugin-dev.nvim: tasks must be a table")
  end
  for name, task in pairs(opts.tasks) do
    if
      type(name) ~= "string"
      or name == ""
      or (type(task) ~= "table" and type(task) ~= "function")
    then
      error("omarchy-plugin-dev.nvim: tasks must map names to tables or functions")
    end
  end
end

---@param opts? OmarchyPluginDevOptions
---@return OmarchyPluginDevConfig
function M.setup(opts)
  local candidate = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  validate(candidate)
  values = candidate
  return values
end

---@return OmarchyPluginDevConfig
function M.get()
  return values
end

function M.user_config_path()
  if not values.config_file then
    return nil
  end
  local path = vim.fs.normalize(values.config_file)
  if path:sub(1, 1) ~= "/" then
    path = vim.fs.joinpath(vim.fn.stdpath("config"), path)
  end
  return path
end

return M
