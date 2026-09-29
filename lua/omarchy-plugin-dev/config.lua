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
---@field tasks? table<string, table|fun(context: table): table?>

---@class OmarchyPluginDevQmlFileContext
---@field manifest table
---@field path string
---@field relative_path string
---@field root string

---@class OmarchyPluginDevConfig
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
  tasks = {},
}

---@type OmarchyPluginDevConfig
local values = vim.deepcopy(defaults)

local function validate(opts)
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
  if opts.mappings ~= false and type(opts.mappings) ~= "table" then
    error("omarchy-plugin-dev.nvim: mappings must be a table or false")
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
  if type(opts.tasks) ~= "table" then
    error("omarchy-plugin-dev.nvim: tasks must be a table")
  end
end

---@param opts? OmarchyPluginDevOptions
---@return OmarchyPluginDevConfig
function M.setup(opts)
  values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  validate(values)
  return values
end

---@return OmarchyPluginDevConfig
function M.get()
  return values
end

return M
