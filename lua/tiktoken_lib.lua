local H = {}
local M = {}

H.get_os_name = function()
  local os_name = vim.loop.os_uname().sysname
  if os_name == "Linux" then
    return "linux"
  elseif os_name == "Darwin" then
    return "macOS"
  elseif os_name == "Windows_NT" then
    return "windows"
  else
    error("Unsupported operating system: " .. os_name)
  end
end

H.library_path = function()
  local os_name = H.get_os_name()
  local ext = os_name == "linux" and "so" or (os_name == "macOS" and "dylib" or "dll")
  local dirname = string.sub(debug.getinfo(1).source, 2, #"/tiktoken_lib.lua" * -1)
  return dirname .. ("../build/?.%s"):format(ext)
end

---@type fun(s: string): string
local trim_semicolon = function(s)
  return s:sub(-1) == ";" and s:sub(1, -2) or s
end

M.load = function()
  local library_path = H.library_path()
  if not string.find(package.cpath, library_path, 1, true) then
    package.cpath = trim_semicolon(package.cpath) .. ";" .. library_path
  end
end

return M
