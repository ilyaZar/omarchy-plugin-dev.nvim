local M = {}

local attached = {}

local definitions = {
  hot_reload = { desc = "Omarchy Plugin: build and restart", method = "hot_reload", force = true },
  rebuild = { desc = "Omarchy Plugin: test, build, and restart", method = "rebuild", force = true },
  test = { desc = "Omarchy Plugin: test", method = "test" },
  menu = { desc = "Omarchy Plugin: project dashboard", method = "dashboard" },
}

local function existing_mapping(bufnr, lhs)
  local mapping = {}
  vim.api.nvim_buf_call(bufnr, function()
    mapping = vim.fn.maparg(lhs, "n", false, true)
  end)
  return type(mapping) == "table" and not vim.tbl_isempty(mapping)
end

function M.detach(bufnr)
  local installed = attached[bufnr]
  if not installed or not vim.api.nvim_buf_is_valid(bufnr) then
    attached[bufnr] = nil
    return
  end
  for _, mapping in ipairs(installed) do
    for _, current in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if current.lhs == mapping.lhs and current.desc == mapping.desc then
        pcall(vim.keymap.del, "n", mapping.configured_lhs, { buffer = bufnr })
        break
      end
    end
  end
  attached[bufnr] = nil
end

function M.attach(bufnr)
  if attached[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local mappings = require("omarchy_plugin_dev.config").get().mappings
  if mappings == false or mappings.enabled == false then
    attached[bufnr] = {}
    return
  end

  attached[bufnr] = {}
  for key, definition in pairs(definitions) do
    local lhs = mappings[key]
    if lhs and lhs ~= false and (definition.force or not existing_mapping(bufnr, lhs)) then
      vim.keymap.set("n", lhs, function()
        require("omarchy_plugin_dev.actions")[definition.method](bufnr)
      end, {
        buffer = bufnr,
        desc = definition.desc,
        silent = true,
      })

      for _, current in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if current.desc == definition.desc then
          attached[bufnr][#attached[bufnr] + 1] = {
            lhs = current.lhs,
            configured_lhs = lhs,
            desc = definition.desc,
          }
          break
        end
      end
    end
  end
end

function M.forget(bufnr)
  attached[bufnr] = nil
end

return M
