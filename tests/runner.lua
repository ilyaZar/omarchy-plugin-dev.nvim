local ok, result = xpcall(function()
  dofile("tests/run.lua")
end, function(error)
  return debug.traceback(tostring(error), 2)
end)

if not ok then
  io.stderr:write(tostring(result) .. "\n")
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
