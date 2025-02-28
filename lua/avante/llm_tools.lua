local curl = require("plenary.curl")
local Utils = require("avante.utils")
local Path = require("plenary.path")
local Config = require("avante.config")
local RagService = require("avante.rag_service")

---@class AvanteRagService
local M = {}

---@param rel_path string
---@return string
local function get_abs_path(rel_path)
  if Path:new(rel_path):is_absolute() then return rel_path end
  local project_root = Utils.get_project_root()
  local p = tostring(Path:new(project_root):joinpath(rel_path):absolute())
  if p:sub(-2) == "/." then p = p:sub(1, -3) end
  return p
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

---@type AvanteLLMToolFunc<{ rel_path: string, max_depth?: integer }>
function M.list_files(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  if on_log then on_log("max depth: " .. tostring(opts.max_depth)) end
  local files = Utils.scan_directory({
    directory = abs_path,
    add_dirs = true,
    max_depth = opts.max_depth,
  })
  local filepaths = {}
  for _, file in ipairs(files) do
    local uniform_path = Utils.uniform_path(file)
    table.insert(filepaths, uniform_path)
  end
  return vim.json.encode(filepaths), nil
end

---@type AvanteLLMToolFunc<{ rel_path: string, keyword: string }>
function M.search_files(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  if on_log then on_log("keyword: " .. opts.keyword) end
  local files = Utils.scan_directory({
    directory = abs_path,
  })
  local filepaths = {}
  for _, file in ipairs(files) do
    if file:find(opts.keyword) then table.insert(filepaths, file) end
  end
  return vim.json.encode(filepaths), nil
end

---@type AvanteLLMToolFunc<{ rel_path: string, keyword: string }>
function M.search_keyword(opts, on_log)
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

---@type AvanteLLMToolFunc<{ rel_path: string }>
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

---@type AvanteLLMToolFunc<{ rel_path: string }>
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

---@type AvanteLLMToolFunc<{ rel_path: string }>
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

---@type AvanteLLMToolFunc<{ rel_path: string, new_rel_path: string }>
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

---@type AvanteLLMToolFunc<{ rel_path: string, new_rel_path: string }>
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

---@type AvanteLLMToolFunc<{ rel_path: string }>
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

---@type AvanteLLMToolFunc<{ rel_path: string }>
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

---@type AvanteLLMToolFunc<{ rel_path: string, new_rel_path: string }>
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

---@type AvanteLLMToolFunc<{ rel_path: string }>
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

---@type AvanteLLMToolFunc<{ rel_path: string, command: string }>
function M.bash(opts, on_log, on_complete)
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
  ---@param output string
  ---@param exit_code integer
  ---@return string | boolean | nil result
  ---@return string | nil error
  local function handle_result(output, exit_code)
    vim.fn.chdir(old_cwd)
    if exit_code ~= 0 then
      if output then return false, "Error: " .. output .. "; Error code: " .. tostring(exit_code) end
      return false, "Error code: " .. tostring(exit_code)
    end
    return output, nil
  end
  if on_complete then
    Utils.shell_run_async(opts.command, "bash -c", function(output, exit_code)
      local result, err = handle_result(output, exit_code)
      on_complete(result, err)
    end)
    return nil, nil
  end
  local res = Utils.shell_run(opts.command, "bash -c")
  return handle_result(res.stdout, res.code)
end

---@type AvanteLLMToolFunc<{ query: string }>
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
  elseif provider_type == "searchapi" then
    local query_params = vim.tbl_deep_extend("force", {
      api_key = api_key,
      q = opts.query,
    }, search_engine.extra_request_body)
    local query_string = ""
    for key, value in pairs(query_params) do
      query_string = query_string .. key .. "=" .. vim.uri_encode(value) .. "&"
    end
    local resp = curl.get("https://searchapi.io/api/v1/search?" .. query_string, {
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
  elseif provider_type == "kagi" then
    local query_params = vim.tbl_deep_extend("force", {
      q = opts.query,
    }, search_engine.extra_request_body)
    local query_string = ""
    for key, value in pairs(query_params) do
      query_string = query_string .. key .. "=" .. vim.uri_encode(value) .. "&"
    end
    local resp = curl.get("https://kagi.com/api/v0/search?" .. query_string, {
      headers = {
        ["Authorization"] = "Bot " .. api_key,
        ["Content-Type"] = "application/json",
      },
    })
    if resp.status ~= 200 then return nil, "Error: " .. resp.body end
    local jsn = vim.json.decode(resp.body)
    return search_engine.format_response_body(jsn)
  end
end

---@type AvanteLLMToolFunc<{ url: string }>
function M.fetch(opts, on_log)
  if on_log then on_log("url: " .. opts.url) end
  local Html2Md = require("avante.html2md")
  local res, err = Html2Md.fetch_md(opts.url)
  if err then return nil, err end
  return res, nil
end

---@type AvanteLLMToolFunc<{ scope?: string }>
function M.git_diff(opts, on_log)
  local git_cmd = vim.fn.exepath("git")
  if git_cmd == "" then return nil, "Git command not found" end
  local project_root = Utils.get_project_root()
  if not project_root then return nil, "Not in a git repository" end

  -- Check if we're in a git repository
  local git_dir = vim.fn.system("git rev-parse --git-dir"):gsub("\n", "")
  if git_dir == "" then return nil, "Not a git repository" end

  -- Get the diff
  local scope = opts.scope or ""
  local cmd = string.format("git diff --cached %s", scope)
  if on_log then on_log("Running command: " .. cmd) end
  local diff = vim.fn.system(cmd)

  if diff == "" then
    -- If there's no staged changes, get unstaged changes
    cmd = string.format("git diff %s", scope)
    if on_log then on_log("No staged changes. Running command: " .. cmd) end
    diff = vim.fn.system(cmd)
  end

  if diff == "" then return nil, "No changes detected" end

  return diff, nil
end

---@type AvanteLLMToolFunc<{ message: string, scope?: string }>
function M.git_commit(opts, on_log)
  local git_cmd = vim.fn.exepath("git")
  if git_cmd == "" then return false, "Git command not found" end
  local project_root = Utils.get_project_root()
  if not project_root then return false, "Not in a git repository" end

  -- Check if we're in a git repository
  local git_dir = vim.fn.system("git rev-parse --git-dir"):gsub("\n", "")
  if git_dir == "" then return false, "Not a git repository" end

  -- First check if there are any changes to commit
  local status = vim.fn.system("git status --porcelain")
  if status == "" then return false, "No changes to commit" end

  -- Get git user name and email
  local git_user = vim.fn.system("git config user.name"):gsub("\n", "")
  local git_email = vim.fn.system("git config user.email"):gsub("\n", "")

  -- Check if GPG signing is available and configured
  local has_gpg = false
  local signing_key = vim.fn.system("git config --get user.signingkey"):gsub("\n", "")

  if signing_key ~= "" then
    -- Try to find gpg executable based on OS
    local gpg_cmd
    if vim.fn.has("win32") == 1 then
      -- Check common Windows GPG paths
      gpg_cmd = vim.fn.exepath("gpg.exe") ~= "" and vim.fn.exepath("gpg.exe") or vim.fn.exepath("gpg2.exe")
    else
      -- Unix-like systems (Linux/MacOS)
      gpg_cmd = vim.fn.exepath("gpg") ~= "" and vim.fn.exepath("gpg") or vim.fn.exepath("gpg2")
    end

    if gpg_cmd ~= "" then
      -- Verify GPG is working
      local _ = vim.fn.system(string.format('"%s" --version', gpg_cmd))
      has_gpg = vim.v.shell_error == 0
    end
  end

  if on_log then on_log(string.format("GPG signing %s", has_gpg and "enabled" or "disabled")) end

  -- Prepare commit message
  local commit_msg_lines = {}
  for line in opts.message:gmatch("[^\r\n]+") do
    commit_msg_lines[#commit_msg_lines + 1] = line:gsub('"', '\\"')
  end
  if git_user ~= "" and git_email ~= "" then
    commit_msg_lines[#commit_msg_lines + 1] = string.format("Signed-off-by: %s <%s>", git_user, git_email)
  end

  -- Construct full commit message for confirmation
  local full_commit_msg = table.concat(commit_msg_lines, "\n")

  -- Confirm with user
  if not M.confirm("Are you sure you want to commit with message:\n" .. full_commit_msg) then
    return false, "User canceled"
  end

  -- Stage changes if scope is provided
  if opts.scope then
    local stage_cmd = string.format("git add %s", opts.scope)
    if on_log then on_log("Staging files: " .. stage_cmd) end
    local stage_result = vim.fn.system(stage_cmd)
    if vim.v.shell_error ~= 0 then return false, "Failed to stage files: " .. stage_result end
  end

  -- Construct git commit command
  local cmd_parts = { "git", "commit" }
  -- Only add -S flag if GPG is available
  if has_gpg then table.insert(cmd_parts, "-S") end
  for _, line in ipairs(commit_msg_lines) do
    table.insert(cmd_parts, "-m")
    table.insert(cmd_parts, '"' .. line .. '"')
  end
  local cmd = table.concat(cmd_parts, " ")

  -- Execute git commit
  if on_log then on_log("Running command: " .. cmd) end
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then return false, "Failed to commit: " .. result end

  return true, nil
end

---@type AvanteLLMToolFunc<{ query: string }>
function M.rag_search(opts, on_log)
  if not Config.rag_service.enabled then return nil, "Rag service is not enabled" end
  if not opts.query then return nil, "No query provided" end
  if on_log then on_log("query: " .. opts.query) end
  local root = Utils.get_project_root()
  local uri = "file://" .. root
  if uri:sub(-1) ~= "/" then uri = uri .. "/" end
  local resp, err = RagService.retrieve(uri, opts.query)
  if err then return nil, err end
  return vim.json.encode(resp), nil
end

---@type AvanteLLMToolFunc<{ code: string, rel_path: string, container_image?: string }>
function M.python(opts, on_log)
  local abs_path = get_abs_path(opts.rel_path)
  if not has_permission_to_access(abs_path) then return nil, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return nil, "Path not found: " .. abs_path end
  if on_log then on_log("cwd: " .. abs_path) end
  if on_log then on_log("code:\n" .. opts.code) end
  local container_image = opts.container_image or "python:3.11-slim-bookworm"
  if
    not M.confirm(
      "Are you sure you want to run the following python code in the `"
        .. container_image
        .. "` container, in the directory: `"
        .. abs_path
        .. "`?\n"
        .. opts.code
    )
  then
    return nil, "User canceled"
  end
  if vim.fn.executable("docker") == 0 then return nil, "Python tool is not available to execute any code" end
  ---change cwd to abs_path
  local old_cwd = vim.fn.getcwd()

  vim.fn.chdir(abs_path)
  local output = vim
    .system({
      "docker",
      "run",
      "--rm",
      "-v",
      abs_path .. ":" .. abs_path,
      "-w",
      abs_path,
      container_image,
      "python",
      "-c",
      opts.code,
    }, {
      text = true,
    })
    :wait()

  vim.fn.chdir(old_cwd)

  if output.code ~= 0 then return nil, "Error: " .. (output.stderr or "Unknown error") end

  Utils.debug("output", output.stdout)
  return output.stdout, nil
end

---@return AvanteLLMTool[]
function M.get_tools()
  return vim
    .iter(M._tools)
    :filter(function(tool)
      if tool.enabled == nil then
        return true
      else
        return tool.enabled()
      end
    end)
    :totable()
end

---@type AvanteLLMTool[]
M._tools = {
  {
    name = "rag_search",
    enabled = function() return Config.rag_service.enabled and RagService.is_ready() end,
    description = "Use Retrieval-Augmented Generation (RAG) to search for relevant information from an external knowledge base or documents. This tool retrieves relevant context from a large dataset and integrates it into the response generation process, improving accuracy and relevance. Use it when answering questions that require factual knowledge beyond what the model has been trained on.",
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
    name = "python",
    description = "Run python code",
    param = {
      type = "table",
      fields = {
        {
          name = "code",
          description = "Python code to run",
          type = "string",
        },
        {
          name = "rel_path",
          description = "Relative path to the directory, as cwd",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "result",
        description = "Python output",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the python code failed",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "git_diff",
    description = "Get git diff for generating commit message",
    param = {
      type = "table",
      fields = {
        {
          name = "scope",
          description = "Scope for the git diff (e.g. specific files or directories)",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "result",
        description = "Git diff output to be used for generating commit message",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the diff generation failed",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "git_commit",
    description = "Commit changes with the given commit message",
    param = {
      type = "table",
      fields = {
        {
          name = "message",
          description = "Commit message to use",
          type = "string",
        },
        {
          name = "scope",
          description = "Scope for staging files (e.g. specific files or directories)",
          type = "string",
          optional = true,
        },
      },
    },
    returns = {
      {
        name = "success",
        description = "True if the commit was successful, false otherwise",
        type = "boolean",
      },
      {
        name = "error",
        description = "Error message if the commit failed",
        type = "string",
        optional = true,
      },
    },
  },
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
          name = "max_depth",
          description = "Maximum depth of the directory",
          type = "integer",
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
    name = "search_keyword",
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
    name = "bash",
    description = "Run a bash command in a directory",
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
---@param on_complete? fun(result: string | nil, error: string | nil): nil
---@return string | nil result
---@return string | nil error
function M.process_tool_use(tools, tool_use, on_log, on_complete)
  Utils.debug("use tool", tool_use.name, tool_use.input_json)
  ---@type AvanteLLMTool?
  local tool = vim.iter(tools):find(function(tool) return tool.name == tool_use.name end) ---@param tool AvanteLLMTool
  if tool == nil then return end
  local input_json = vim.json.decode(tool_use.input_json)
  local func = tool.func or M[tool.name]
  if on_log then on_log(tool.name, "running tool") end
  ---@param result string | nil | boolean
  ---@param err string | nil
  local function handle_result(result, err)
    if on_log then on_log(tool.name, "tool finished") end
    -- Utils.debug("result", result)
    -- Utils.debug("error", error)
    if err ~= nil then
      if on_log then on_log(tool.name, "Error: " .. err) end
    end
    local result_str ---@type string?
    if type(result) == "string" then
      result_str = result
    elseif result ~= nil then
      result_str = vim.json.encode(result)
    end
    return result_str, err
  end
  local result, err = func(input_json, function(log)
    if on_log then on_log(tool.name, log) end
  end, function(result, err)
    result, err = handle_result(result, err)
    if on_complete == nil then
      Utils.error("asynchronous tool " .. tool.name .. " result not handled")
      return
    end
    on_complete(result, err)
  end)
  -- Result and error being nil means that the tool was executed asynchronously
  if result == nil and err == nil and on_complete then return end
  return handle_result(result, err)
end

---@param tool_use AvanteLLMToolUse
---@return string
function M.stringify_tool_use(tool_use)
  local s = string.format("`%s`", tool_use.name)
  return s
end

return M
