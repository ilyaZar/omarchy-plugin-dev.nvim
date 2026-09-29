local M = {}

local configured = false

local function first_lines(path, bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, 10, false)
    if ok then
      return lines
    end
  end

  local ok, lines = pcall(vim.fn.readfile, path, "", 10)
  return ok and lines or {}
end

function M.is_qml_javascript(path, bufnr)
  if type(path) ~= "string" or not path:lower():match("%.js$") then
    return false
  end
  for _, line in ipairs(first_lines(path, bufnr)) do
    if line:match("^%s*%.pragma%s+library%s*$") then
      return true
    end
  end
  return false
end

function M.detect(path, bufnr)
  return M.is_qml_javascript(path, bufnr) and "qmljs" or nil
end

function M.setup()
  if configured then
    return
  end
  configured = true
  vim.treesitter.language.register("javascript", "qmljs")
  vim.filetype.add({
    pattern = {
      [".*%.js"] = { M.detect, { priority = 10 } },
    },
  })
end

return M
