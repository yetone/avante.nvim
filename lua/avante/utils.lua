local M = {}

function M.trim_suffix(str, suffix)
  return string.gsub(str, suffix .. "$", "")
end

function M.escape(str)
  return string.gsub(str, "([%(%)%.%%%+%-%*%?%[%^%$%]])", "%%%1")
end

return M
