local ok, result = xpcall(function()
  dofile("tests/run.lua")
end, function(error)
  return debug.traceback(tostring(error), 2)
end)

if not ok then
  io.stderr:write(tostring(result) .. "\n")
  vim.cmd("cquit 1")
else
  vim.lsp.enable("omarchy_plugin_dev", false)
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop(true)
  end
  vim.wait(1000, function()
    return #vim.lsp.get_clients() == 0
  end)
  vim.cmd("qa!")
end
