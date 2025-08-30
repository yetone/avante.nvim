-- This is a helper for unit tests.
local M = {}

function M.read_file(fn)
  fn = vim.uv.cwd() .. "/" .. fn
  local file = io.open(fn, "r")
  if file then
    local data = file:read("*all")
    file:close()
    return data
  end
  return fn
end

return M
