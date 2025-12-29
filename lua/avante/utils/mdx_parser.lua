local Utils = require("avante.utils")

---@class avante.MDXParser
local M = {}

---Parse YAML front-matter from a string
---@param content string
---@return table|nil, string|nil error
local function parse_front_matter(content)
  -- Match content between --- markers
  local front_matter = content:match("^%-%-%-\n(.-)\n%-%-%-")
  if not front_matter then
    return nil, "No front-matter found"
  end

  -- Simple YAML parser for our needs (name: value pairs)
  local parsed = {}
  for line in front_matter:gmatch("[^\r\n]+") do
    local key, value = line:match("^(%w+):%s*(.+)$")
    if key and value then
      -- Remove quotes if present
      value = value:gsub("^['\"](.+)['\"]$", "%1")
      parsed[key] = value
    end
  end

  return parsed, nil
end

---Extract the body content (after front-matter)
---@param content string
---@return string|nil
local function extract_body(content)
  -- Find content after the closing ---
  local _, end_pos = content:find("^%-%-%-\n.-\n%-%-%-\n")
  if end_pos then
    return content:sub(end_pos + 1):match("^%s*(.-)%s*$") -- trim whitespace
  end
  return nil
end

---Parse an MDX file and extract shortcut information
---@param filepath string
---@return AvanteShortcut|nil, string|nil error
function M.parse_mdx_file(filepath)
  -- Read file content
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Failed to open file: " .. filepath
  end

  local content = file:read("*all")
  file:close()

  if not content or content == "" then
    return nil, "Empty file: " .. filepath
  end

  -- Parse front-matter
  local front_matter, err = parse_front_matter(content)
  if not front_matter then
    return nil, "Failed to parse front-matter in " .. filepath .. ": " .. (err or "unknown error")
  end

  -- Extract body (this will be the prompt if not in front-matter)
  local body = extract_body(content)

  -- Build shortcut object
  ---@type AvanteShortcut
  local shortcut = {
    name = front_matter.name,
    description = front_matter.description,
    details = front_matter.details or front_matter.description,
    prompt = front_matter.prompt or body or "",
  }

  -- Validate required fields
  if not shortcut.name or shortcut.name == "" then
    return nil, "Missing required field 'name' in " .. filepath
  end

  if not shortcut.prompt or shortcut.prompt == "" then
    return nil, "Missing prompt (either in front-matter or body) in " .. filepath
  end

  return shortcut, nil
end

---Load all MDX shortcuts from a directory
---@param directory string
---@return AvanteShortcut[]
function M.load_shortcuts_from_directory(directory)
  local shortcuts = {}

  -- Expand path
  local dir_path = vim.fn.expand(directory)

  -- Check if directory exists
  if vim.fn.isdirectory(dir_path) ~= 1 then
    Utils.debug("Shortcuts directory does not exist: " .. dir_path)
    return shortcuts
  end

  -- Find all .mdx files
  local mdx_files = vim.fn.glob(dir_path .. "/*.mdx", false, true)

  for _, filepath in ipairs(mdx_files) do
    local shortcut, err = M.parse_mdx_file(filepath)
    if shortcut then
      table.insert(shortcuts, shortcut)
      Utils.debug("Loaded shortcut '" .. shortcut.name .. "' from " .. filepath)
    else
      -- Only warn in debug mode to avoid cluttering user output
      Utils.debug("Failed to parse MDX shortcut file " .. filepath .. ": " .. (err or "unknown error"))
    end
  end

  Utils.debug("Loaded " .. #shortcuts .. " shortcuts from " .. dir_path)
  return shortcuts
end

return M
