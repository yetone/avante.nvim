local M = {}

function M.trim_suffix(str, suffix)
  return string.gsub(str, suffix .. "$", "")
end

function M.trim_line_number_prefix(line)
  return line:gsub("^L%d+: ", "")
end

return M
