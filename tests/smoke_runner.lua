local ok, result = xpcall(function()
  dofile("tests/smoke.lua")
end, debug.traceback)

if not ok then
  io.stderr:write(tostring(result) .. "\n")
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
