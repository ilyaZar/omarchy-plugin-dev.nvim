local ok, result = xpcall(function()
  dofile("tests/run.lua")
end, function(error)
  return debug.traceback(tostring(error), 2)
end)

if not ok then
  vim.api.nvim_err_writeln(tostring(result))
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
