local M = {}

local function get_library_path()
  local os_name = require("avante.utils").get_os_name()
  local ext = os_name == "linux" and "so" or (os_name == "darwin" and "dylib" or "dll")
  local dirname = string.sub(debug.getinfo(1).source, 2, #"/avante_lib.lua" * -1)
  return dirname .. ("../build/?.%s"):format(ext)
end

---@type fun(s: string): string
local trim_semicolon = function(s) return s:sub(-1) == ";" and s:sub(1, -2) or s end

M.load = function()
  local library_path = get_library_path()
  if not string.find(package.cpath, library_path, 1, true) then
    package.cpath = trim_semicolon(package.cpath) .. ";" .. library_path
  end
end

return M
