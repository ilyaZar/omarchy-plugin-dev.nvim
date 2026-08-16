local ok, result = xpcall(function()
  dofile("tests/smoke.lua")
end, debug.traceback)

if not ok then
  vim.api.nvim_err_writeln(result)
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
