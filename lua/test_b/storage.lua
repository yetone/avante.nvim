-- Storage Utility Module
-- Provides JSON-based persistence following XDG standards

local M = {}

-- Get the base data directory following XDG standards
-- @return string Path to data directory
function M.get_data_dir()
  local data_dir = vim.fn.stdpath("data") .. "/test-b"
  return data_dir
end

-- Ensure directory exists, creating if necessary
-- @param path string Directory path
-- @return boolean Success status
local function ensure_dir(path)
  local stat = vim.loop.fs_stat(path)
  if not stat then
    local success = vim.fn.mkdir(path, "p")
    return success == 1
  end
  return true
end

-- Read JSON data from file
-- @param filename string Filename within data directory
-- @return table|nil Data table or nil on error
-- @return string|nil Error message if failed
function M.read(filename)
  local data_dir = M.get_data_dir()
  local filepath = data_dir .. "/" .. filename

  local file = io.open(filepath, "r")
  if not file then
    return nil, "File not found: " .. filepath
  end

  local content = file:read("*all")
  file:close()

  if not content or content == "" then
    return {}, nil
  end

  local success, data = pcall(vim.json.decode, content)
  if not success then
    return nil, "Failed to decode JSON: " .. tostring(data)
  end

  return data, nil
end

-- Write JSON data to file
-- @param filename string Filename within data directory
-- @param data table Data to write
-- @return boolean Success status
-- @return string|nil Error message if failed
function M.write(filename, data)
  local data_dir = M.get_data_dir()

  if not ensure_dir(data_dir) then
    return false, "Failed to create data directory: " .. data_dir
  end

  local filepath = data_dir .. "/" .. filename

  local success, json = pcall(vim.json.encode, data)
  if not success then
    return false, "Failed to encode JSON: " .. tostring(json)
  end

  local file = io.open(filepath, "w")
  if not file then
    return false, "Failed to open file for writing: " .. filepath
  end

  file:write(json)
  file:close()

  return true, nil
end

-- Delete a file from storage
-- @param filename string Filename within data directory
-- @return boolean Success status
function M.delete(filename)
  local data_dir = M.get_data_dir()
  local filepath = data_dir .. "/" .. filename

  local success = os.remove(filepath)
  return success ~= nil
end

-- Check if file exists
-- @param filename string Filename within data directory
-- @return boolean True if file exists
function M.exists(filename)
  local data_dir = M.get_data_dir()
  local filepath = data_dir .. "/" .. filename

  local file = io.open(filepath, "r")
  if file then
    file:close()
    return true
  end
  return false
end

return M
