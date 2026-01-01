local curl = require("plenary.curl")
local M = {}

---Posts JSON body to URL
---@param url string URL to post to
---@param body table Lua table to encode as JSON
---@param headers table<string, string>|nil Additional headers
---@return table?, string? response value of response body or error
function M.post_json(url, body, headers)
  -- Merge headers, ensuring Content-Type is set
  local request_headers = vim.tbl_extend("force", {
    ["Content-Type"] = "application/json",
  }, headers or {})

  local response = curl.post(url, {
    body = vim.json.encode(body),
    headers = request_headers,
  })

  if response.status >= 400 then return nil, string.format("HTTP %d: %s", response.status, response.body) end
  local ok, decoded = pcall(vim.json.decode, response.body)
  if ok then
    return decoded, nil
  else
    return nil, "Failed to decode JSON: " .. tostring(decoded)
  end
end

return M
