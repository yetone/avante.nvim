local curl = require("plenary.curl")
local Utils = require("avante.utils")
local Path = require("plenary.path")
local Config = require("avante.config")
local M = {}

---@param rel_path string
---@return string
local function get_abs_path(rel_path)
  if Path:new(rel_path):is_absolute() then return rel_path end
  local project_root = Utils.get_project_root()
  return Path:new(project_root):joinpath(rel_path):absolute()
end

function M.confirm(msg)
  local ok = vim.fn.confirm(msg, "&Yes\n&No", 2)
  return ok == 1
end

---@param abs_path string
---@return boolean
local function has_permission_to_access(abs_path)
  if not Path:new(abs_path):is_absolute() then return false end
  local project_root = Utils.get_project_root()
  if abs_path:sub(1, #project_root) ~= project_root then return false end
  local gitignore_path = project_root .. "/.gitignore"
  local gitignore_patterns, gitignore_negate_patterns = Utils.parse_gitignore(gitignore_path)
  return not Utils.is_ignored(abs_path, gitignore_patterns, gitignore_negate_patterns)
end

---@param opts { rel_path: string, depth?: integer }
---@param on_log? fun(log: string): nil
---@return string files
---@return string|nil error
function M.list_files(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  if on_log then on_log("depth: " .. tostring(opts.depth)) end
  local files = Utils.scan_directory_respect_gitignore({
    directory = abs_path,
    add_dirs = true,
    depth = opts.depth,
  })
  local filepaths = {}
  for _, file in ipairs(files) do
    local uniform_path = Utils.uniform_path(file)
    table.insert(filepaths, uniform_path)
  end
  return vim.json.encode(filepaths), nil
end

---@param opts { rel_path: string, keyword: string }
---@param on_log? fun(log: string): nil
---@return string files
---@return string|nil error
function M.search_files(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  if on_log then on_log("keyword: " .. opts.keyword) end
  local files = Utils.scan_directory_respect_gitignore({
    directory = abs_path,
  })
  local filepaths = {}
  for _, file in ipairs(files) do
    if file:find(opts.keyword) then table.insert(filepaths, file) end
  end
  return vim.json.encode(filepaths), nil
end

---@param opts { rel_path: string, keyword: string }
---@param on_log? fun(log: string): nil
---@return string result
---@return string|nil error
function M.search(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return "", "No such file or directory: " .. abs_path end

  ---check if any search cmd is available
  local search_cmd = vim.fn.exepath("rg")
  if search_cmd == "" then search_cmd = vim.fn.exepath("ag") end
  if search_cmd == "" then search_cmd = vim.fn.exepath("ack") end
  if search_cmd == "" then search_cmd = vim.fn.exepath("grep") end
  if search_cmd == "" then return "", "No search command found" end

  ---execute the search command
  local cmd = ""
  if search_cmd:find("rg") then
    cmd = string.format("%s --files-with-matches --no-ignore-vcs --ignore-case --hidden --glob '!.git'", search_cmd)
    cmd = string.format("%s '%s' %s", cmd, opts.keyword, abs_path)
  elseif search_cmd:find("ag") then
    cmd = string.format("%s '%s' --nocolor --nogroup --hidden --ignore .git %s", search_cmd, opts.keyword, abs_path)
  elseif search_cmd:find("ack") then
    cmd = string.format("%s --nocolor --nogroup --hidden --ignore-dir .git", search_cmd)
    cmd = string.format("%s '%s' %s", cmd, opts.keyword, abs_path)
  elseif search_cmd:find("grep") then
    cmd = string.format("%s -riH --exclude-dir=.git %s %s", search_cmd, opts.keyword, abs_path)
  end

  Utils.debug("cmd", cmd)
  if on_log then on_log("Running command: " .. cmd) end
  local result = vim.fn.system(cmd)

  local filepaths = vim.split(result, "\n")

  return vim.json.encode(filepaths), nil
end

---@param opts { rel_path: string }
---@param on_log? fun(log: string): nil
---@return string definitions
---@return string|nil error
function M.read_file_toplevel_symbols(opts, on_log)
  local RepoMap = require("avante.repo_map")
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  if not Path:new(abs_path):exists() then return "", "File does not exists: " .. abs_path end
  local filetype = RepoMap.get_ts_lang(abs_path)
  local repo_map_lib = RepoMap._init_repo_map_lib()
  if not repo_map_lib then return "", "Failed to load avante_repo_map" end
  local lines = Utils.read_file_from_buf_or_disk(abs_path)
  local content = lines and table.concat(lines, "\n") or ""
  local definitions = filetype and repo_map_lib.stringify_definitions(filetype, content) or ""
  return definitions, nil
end

---@param opts { rel_path: string }
---@param on_log? fun(log: string): nil
---@return string content
---@return string|nil error
function M.read_file(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  local file = io.open(abs_path, "r")
  if not file then return "", "file not found: " .. abs_path end
  local content = file:read("*a")
  file:close()
  return content, nil
end

---@param opts { rel_path: string }
---@param on_log? fun(log: string): nil
---@return boolean success
---@return string|nil error
function M.create_file(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  ---create directory if it doesn't exist
  local dir = Path:new(abs_path):parent()
  if not dir:exists() then dir:mkdir({ parents = true }) end
  ---create file if it doesn't exist
  if not dir:joinpath(opts.rel_path):exists() then
    local file = io.open(abs_path, "w")
    if not file then return false, "file not found: " .. abs_path end
    file:close()
  end

  return true, nil
end

---@param opts { rel_path: string, new_rel_path: string }
---@param on_log? fun(log: string): nil
---@return boolean success
---@return string|nil error
function M.rename_file(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
  if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
  local new_abs_path = get_abs_path(opts.new_rel_path)
  if on_log then on_log(abs_path .. " -> " .. new_abs_path) end
  if not has_permission_to_access(new_abs_path) then return false, "No permission to access path: " .. new_abs_path end
  if Path:new(new_abs_path):exists() then return false, "File already exists: " .. new_abs_path end
  if not M.confirm("Are you sure you want to rename the file: " .. abs_path .. " to: " .. new_abs_path) then
    return false, "User canceled"
  end
  os.rename(abs_path, new_abs_path)
  return true, nil
end

---@param opts { rel_path: string, new_rel_path: string }
---@param on_log? fun(log: string): nil
---@return boolean success
---@return string|nil error
function M.copy_file(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
  if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
  local new_abs_path = get_abs_path(opts.new_rel_path)
  if not has_permission_to_access(new_abs_path) then return false, "No permission to access path: " .. new_abs_path end
  if Path:new(new_abs_path):exists() then return false, "File already exists: " .. new_abs_path end
  if on_log then on_log("Copying file: " .. abs_path .. " to " .. new_abs_path) end
  Path:new(new_abs_path):write(Path:new(abs_path):read())
  return true, nil
end

---@param opts { rel_path: string }
---@param on_log? fun(log: string): nil
---@return boolean success
---@return string|nil error
function M.delete_file(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
  if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
  if not M.confirm("Are you sure you want to delete the file: " .. abs_path) then return false, "User canceled" end
  if on_log then on_log("Deleting file: " .. abs_path) end
  os.remove(abs_path)
  return true, nil
end

---@param opts { rel_path: string }
---@param on_log? fun(log: string): nil
---@return boolean success
---@return string|nil error
function M.create_dir(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if Path:new(abs_path):exists() then return false, "Directory already exists: " .. abs_path end
  if not M.confirm("Are you sure you want to create the directory: " .. abs_path) then
    return false, "User canceled"
  end
  if on_log then on_log("Creating directory: " .. abs_path) end
  Path:new(abs_path):mkdir({ parents = true })
  return true, nil
end

---@param opts { rel_path: string, new_rel_path: string }
---@param on_log? fun(log: string): nil
---@return boolean success
---@return string|nil error
function M.rename_dir(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "Directory not found: " .. abs_path end
  if not Path:new(abs_path):is_dir() then return false, "Path is not a directory: " .. abs_path end
  local new_abs_path = get_abs_path(opts.new_rel_path)
  if not has_permission_to_access(new_abs_path) then return false, "No permission to access path: " .. new_abs_path end
  if Path:new(new_abs_path):exists() then return false, "Directory already exists: " .. new_abs_path end
  if not M.confirm("Are you sure you want to rename directory " .. abs_path .. " to " .. new_abs_path .. "?") then
    return false, "User canceled"
  end
  if on_log then on_log("Renaming directory: " .. abs_path .. " to " .. new_abs_path) end
  os.rename(abs_path, new_abs_path)
  return true, nil
end

---@param opts { rel_path: string }
---@param on_log? fun(log: string): nil
---@return boolean success
---@return string|nil error
function M.delete_dir(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "Directory not found: " .. abs_path end
  if not Path:new(abs_path):is_dir() then return false, "Path is not a directory: " .. abs_path end
  if not M.confirm("Are you sure you want to delete the directory: " .. abs_path) then
    return false, "User canceled"
  end
  if on_log then on_log("Deleting directory: " .. abs_path) end
  os.remove(abs_path)
  return true, nil
end

---@param opts { rel_path: string, command: string }
---@param on_log? fun(log: string): nil
---@return string|boolean result
---@return string|nil error
function M.run_command(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "Path not found: " .. abs_path end
  if on_log then on_log("command: " .. opts.command) end
  if
    not M.confirm("Are you sure you want to run the command: `" .. opts.command .. "` in the directory: " .. abs_path)
  then
    return false, "User canceled"
  end
  ---change cwd to abs_path
  local old_cwd = vim.fn.getcwd()
  vim.fn.chdir(abs_path)
  local res = Utils.shell_run(opts.command)
  vim.fn.chdir(old_cwd)
  if res.code ~= 0 then
    if res.stdout then return false, "Error: " .. res.stdout .. "; Error code: " .. tostring(res.code) end
    return false, "Error code: " .. tostring(res.code)
  end
  return res.stdout, nil
end

---@param opts { query: string }
---@param on_log? fun(log: string): nil
---@return string|nil result
---@return string|nil error
function M.web_search(opts, on_log)
  local provider_type = Config.web_search_engine.provider
  if provider_type == nil then return nil, "Search engine provider is not set" end
  if on_log then on_log("provider: " .. provider_type) end
  if on_log then on_log("query: " .. opts.query) end
  local search_engine = Config.web_search_engine.providers[provider_type]
  if search_engine == nil then return nil, "No search engine found: " .. provider_type end
  if search_engine.api_key_name == "" then return nil, "No API key provided" end
  local api_key = os.getenv(search_engine.api_key_name)
  if api_key == nil or api_key == "" then
    return nil, "Environment variable " .. search_engine.api_key_name .. " is not set"
  end
  if provider_type == "tavily" then
    local resp = curl.post("https://api.tavily.com/search", {
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
      },
      body = vim.json.encode(vim.tbl_deep_extend("force", {
        query = opts.query,
      }, search_engine.extra_request_body)),
    })
    if resp.status ~= 200 then return nil, "Error: " .. resp.body end
    local jsn = vim.json.decode(resp.body)
    return search_engine.format_response_body(jsn)
  elseif provider_type == "serpapi" then
    local query_params = vim.tbl_deep_extend("force", {
      api_key = api_key,
      q = opts.query,
    }, search_engine.extra_request_body)
    local query_string = ""
    for key, value in pairs(query_params) do
      query_string = query_string .. key .. "=" .. vim.uri_encode(value) .. "&"
    end
    local resp = curl.get("https://serpapi.com/search?" .. query_string, {
      headers = {
        ["Content-Type"] = "application/json",
      },
    })
    if resp.status ~= 200 then return nil, "Error: " .. resp.body end
    local jsn = vim.json.decode(resp.body)
    return search_engine.format_response_body(jsn)
  elseif provider_type == "google" then
    local engine_id = os.getenv(search_engine.engine_id_name)
    if engine_id == nil or engine_id == "" then
      return nil, "Environment variable " .. search_engine.engine_id_namee .. " is not set"
    end
    local query_params = vim.tbl_deep_extend("force", {
      key = api_key,
      cx = engine_id,
      q = opts.query,
    }, search_engine.extra_request_body)
    local query_string = ""
    for key, value in pairs(query_params) do
      query_string = query_string .. key .. "=" .. vim.uri_encode(value) .. "&"
    end
    local resp = curl.get("https://www.googleapis.com/customsearch/v1?" .. query_string, {
      headers = {
        ["Content-Type"] = "application/json",
      },
    })
    if resp.status ~= 200 then return nil, "Error: " .. resp.body end
    local jsn = vim.json.decode(resp.body)
    return search_engine.format_response_body(jsn)
  end
end

---@param opts { url: string }
---@param on_log? fun(log: string): nil
---@return string|nil result
---@return string|nil error
function M.fetch(opts, on_log)
  if on_log then on_log("url: " .. opts.url) end
  local Html2Md = require("avante.html2md")
  local res = Html2Md.fetch_md(opts.url)
  if res == nil then return nil, "Failed to fetch markdown" end
  return res, nil
end

---@class AvanteLLMTool
---@field name string
---@field description string
---@field func? fun(input: any): (string | nil, string | nil)
---@field param AvanteLLMToolParam
---@field returns AvanteLLMToolReturn[]

---@class AvanteLLMToolParam
---@field type string
---@field fields AvanteLLMToolParamField[]

---@class AvanteLLMToolParamField
---@field name string
---@field description string
---@field type string
---@field optional? boolean

---@class AvanteLLMToolReturn
---@field name string
---@field description string
---@field type string
---@field optional? boolean

---@type AvanteLLMTool[]
M.tools = {
  {
    name = "list_files",
    description = "List files in a directory",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the directory",
          type = "string",
        },
        {
          name = "depth",
          description = "Depth of the directory",
          type = "integer",
          optional = true,
        },
      },
    },
    returns = {
      {
        name = "files",
        description = "List of files in the directory",
        type = "string[]",
      },
      {
        name = "error",
        description = "Error message if the directory was not listed successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "search_files",
    description = "Search for files in a directory",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the directory",
          type = "string",
        },
        {
          name = "keyword",
          description = "Keyword to search for",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "files",
        description = "List of files that match the keyword",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the directory was not searched successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "search",
    description = "Search for a keyword in a directory",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the directory",
          type = "string",
        },
        {
          name = "keyword",
          description = "Keyword to search for",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "files",
        description = "List of files that match the keyword",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the directory was not searched successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "read_file_toplevel_symbols",
    description = "Read the top-level symbols of a file",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the file",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "definitions",
        description = "Top-level symbols of the file",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the file was not read successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "read_file",
    description = "Read the contents of a file",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the file",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "content",
        description = "Contents of the file",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the file was not read successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "create_file",
    description = "Create a new file",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the file",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "success",
        description = "True if the file was created successfully, false otherwise",
        type = "boolean",
      },
      {
        name = "error",
        description = "Error message if the file was not created successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "rename_file",
    description = "Rename a file",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the file",
          type = "string",
        },
        {
          name = "new_rel_path",
          description = "New relative path for the file",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "success",
        description = "True if the file was renamed successfully, false otherwise",
        type = "boolean",
      },
      {
        name = "error",
        description = "Error message if the file was not renamed successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "delete_file",
    description = "Delete a file",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the file",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "success",
        description = "True if the file was deleted successfully, false otherwise",
        type = "boolean",
      },
      {
        name = "error",
        description = "Error message if the file was not deleted successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "create_dir",
    description = "Create a new directory",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the directory",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "success",
        description = "True if the directory was created successfully, false otherwise",
        type = "boolean",
      },
      {
        name = "error",
        description = "Error message if the directory was not created successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "rename_dir",
    description = "Rename a directory",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the directory",
          type = "string",
        },
        {
          name = "new_rel_path",
          description = "New relative path for the directory",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "success",
        description = "True if the directory was renamed successfully, false otherwise",
        type = "boolean",
      },
      {
        name = "error",
        description = "Error message if the directory was not renamed successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "delete_dir",
    description = "Delete a directory",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the directory",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "success",
        description = "True if the directory was deleted successfully, false otherwise",
        type = "boolean",
      },
      {
        name = "error",
        description = "Error message if the directory was not deleted successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "run_command",
    description = "Run a command in a directory",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the directory",
          type = "string",
        },
        {
          name = "command",
          description = "Command to run",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "stdout",
        description = "Output of the command",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the command was not run successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "web_search",
    description = "Search the web",
    param = {
      type = "table",
      fields = {
        {
          name = "query",
          description = "Query to search",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "result",
        description = "Result of the search",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the search was not successful",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "fetch",
    description = "Fetch markdown from a url",
    param = {
      type = "table",
      fields = {
        {
          name = "url",
          description = "Url to fetch markdown from",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "result",
        description = "Result of the fetch",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the fetch was not successful",
        type = "string",
        optional = true,
      },
    },
  },
}

---@param tools AvanteLLMTool[]
---@param tool_use AvanteLLMToolUse
---@param on_log? fun(tool_name: string, log: string): nil
---@return string | nil result
---@return string | nil error
function M.process_tool_use(tools, tool_use, on_log)
  Utils.debug("use tool", tool_use.name, tool_use.input_json)
  local tool = vim.iter(tools):find(function(tool) return tool.name == tool_use.name end)
  if tool == nil then return end
  local input_json = vim.json.decode(tool_use.input_json)
  local func = tool.func or M[tool.name]
  if on_log then on_log(tool_use.name, "running tool") end
  local result, error = func(input_json, function(log)
    if on_log then on_log(tool_use.name, log) end
  end)
  if on_log then on_log(tool_use.name, "tool finished") end
  -- Utils.debug("result", result)
  -- Utils.debug("error", error)
  if error ~= nil then
    if on_log then on_log(tool_use.name, "Error: " .. error) end
  end
  if result ~= nil and type(result) ~= "string" then result = vim.json.encode(result) end
  return result, error
end

---@param tool_use AvanteLLMToolUse
---@return string
function M.stringify_tool_use(tool_use)
  local s = string.format("`%s`", tool_use.name)
  return s
end

return M
