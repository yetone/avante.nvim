-- Storage module for persisting data to JSON files
local M = {}

local storage_path = ".something/data"

-- Initialize storage system
function M.init(path)
  storage_path = path or storage_path
  -- Create directory if it doesn't exist
  vim.fn.mkdir(storage_path, "p")
end

-- Read JSON file
function M.read(filename)
  local filepath = storage_path .. "/" .. filename .. ".json"
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end

  local content = file:read("*all")
  file:close()

  if content == "" then
    return nil
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end

  return data
end

-- Write JSON file
function M.write(filename, data)
  local filepath = storage_path .. "/" .. filename .. ".json"
  local content = vim.json.encode(data)

  local file = io.open(filepath, "w")
  if not file then
    return false, "Failed to open file for writing"
  end

  file:write(content)
  file:close()

  return true
end

-- Check if file exists
function M.exists(filename)
  local filepath = storage_path .. "/" .. filename .. ".json"
  local file = io.open(filepath, "r")
  if file then
    file:close()
    return true
  end
  return false
end

-- Delete file
function M.delete(filename)
  local filepath = storage_path .. "/" .. filename .. ".json"
  return os.remove(filepath) ~= nil
end

-- Get current timestamp in ISO 8601 format
function M.timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- Generate UUID v4
function M.uuid()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format("%x", v)
  end)
end

return M
