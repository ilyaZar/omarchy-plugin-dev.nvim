local M = {}
local held = {}

function M.acquire(id)
  if held[id] then
    return nil, "Another build or source selection is running for " .. id
  end
  local ready, finished, output = false, false, ""
  local process
  local function release()
    if process then
      pcall(process.write, process, nil)
      process = nil
    end
    held[id] = nil
  end
  held[id] = release
  local ok, result = pcall(vim.system, {
    require("omarchy-plugin-dev.targets").script("operation-lock"),
    id,
  }, {
    stdin = true,
    text = true,
    stdout = function(err, data)
      if err then
        output = output .. tostring(err)
      end
      if data then
        output = output .. data
        ready = output:find("locked\n", 1, true) ~= nil
      end
    end,
  }, function(completed)
    finished = true
    if completed.code ~= 0 then
      output = completed.stderr or output
    end
  end)
  if not ok then
    release()
    return nil, tostring(result)
  end
  process = result
  vim.wait(2000, function()
    return ready or finished
  end, 10)
  if not ready or finished then
    pcall(process.kill, process, 15)
    release()
    return nil, vim.trim(output) ~= "" and vim.trim(output) or "Could not acquire the build lock"
  end
  return release
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("omarchy_plugin_dev_operations", { clear = true }),
  callback = function()
    for _, release in pairs(vim.tbl_extend("force", {}, held)) do
      release()
    end
  end,
})

return M
