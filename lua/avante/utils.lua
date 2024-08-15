local M = {}

function M.trim_suffix(str, suffix)
  return string.gsub(str, suffix .. "$", "")
end

return M
