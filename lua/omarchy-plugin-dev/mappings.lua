local M = {}

local attached = {}

local definitions = {
  hot_reload = { desc = "Omarchy Plugin: build and restart", method = "hot_reload", force = true },
  build = { desc = "Omarchy Plugin: test, build, and restart", method = "build", force = true },
  test = { desc = "Omarchy Plugin: test", method = "test" },
  menu = { desc = "Omarchy Plugin: project dashboard", method = "dashboard" },
}

local function current_mapping(bufnr, lhs)
  local mapping = {}
  vim.api.nvim_buf_call(bufnr, function()
    mapping = vim.fn.maparg(lhs, "n", false, true)
  end)
  return type(mapping) == "table" and not vim.tbl_isempty(mapping) and mapping or nil
end

function M.detach(bufnr)
  local installed = attached[bufnr]
  if not installed or not vim.api.nvim_buf_is_valid(bufnr) then
    attached[bufnr] = nil
    return
  end
  for index = #installed, 1, -1 do
    local mapping = installed[index]
    if vim.deep_equal(current_mapping(bufnr, mapping.lhs), mapping.installed) then
      vim.keymap.del("n", mapping.lhs, { buffer = bufnr })
      if mapping.previous then
        vim.api.nvim_buf_call(bufnr, function()
          vim.fn.mapset(mapping.previous)
        end)
      end
    end
  end
  attached[bufnr] = nil
end

function M.attach(bufnr)
  if attached[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local mappings = require("omarchy-plugin-dev.config").get().mappings
  if mappings == false or mappings.enabled == false then
    attached[bufnr] = {}
    return
  end

  attached[bufnr] = {}
  for key, definition in pairs(definitions) do
    local lhs = mappings[key]
    local previous = lhs and current_mapping(bufnr, lhs)
    if lhs and lhs ~= false and (definition.force or not previous) then
      vim.keymap.set("n", lhs, function()
        require("omarchy-plugin-dev.actions")[definition.method](bufnr)
      end, {
        buffer = bufnr,
        desc = definition.desc,
        silent = true,
      })

      attached[bufnr][#attached[bufnr] + 1] = {
        lhs = lhs,
        installed = current_mapping(bufnr, lhs),
        previous = previous and previous.buffer == 1 and previous or nil,
      }
    end
  end
end

function M.forget(bufnr)
  attached[bufnr] = nil
end

return M
