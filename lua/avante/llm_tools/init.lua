local curl = require("plenary.curl")
local Utils = require("avante.utils")
local Path = require("plenary.path")
local Config = require("avante.config")
local RagService = require("avante.rag_service")
local Helpers = require("avante.llm_tools.helpers")

local M = {}

---@type AvanteLLMToolFunc<{ rel_path: string }>
function M.read_file_toplevel_symbols(opts, on_log)
  local RepoMap = require("avante.repo_map")
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return "", "No permission to access path: " .. abs_path end
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

---@type AvanteLLMToolFunc<{ command: "view" | "str_replace" | "create" | "insert" | "undo_edit", path: string, old_str?: string, new_str?: string, file_text?: string, insert_line?: integer, new_str?: string, view_range?: integer[] }>
function M.str_replace_editor(opts, on_log, on_complete, session_ctx)
  if on_log then on_log("command: " .. opts.command) end
  if not on_complete then return false, "on_complete not provided" end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if opts.command == "view" then
    local view = require("avante.llm_tools.view")
    local opts_ = { path = opts.path }
    if opts.view_range then
      local start_line, end_line = unpack(opts.view_range)
      opts_.view_range = {
        start_line = start_line,
        end_line = end_line,
      }
    end
    return view(opts_, on_log, on_complete, session_ctx)
  end
  if opts.command == "str_replace" then
    return require("avante.llm_tools.str_replace").func(opts, on_log, on_complete, session_ctx)
  end
  if opts.command == "create" then
    return require("avante.llm_tools.create").func(opts, on_log, on_complete, session_ctx)
  end
  if opts.command == "insert" then
    return require("avante.llm_tools.insert").func(opts, on_log, on_complete, session_ctx)
  end
  if opts.command == "undo_edit" then
    return require("avante.llm_tools.undo_edit").func(opts, on_log, on_complete, session_ctx)
  end
  return false, "Unknown command: " .. opts.command
end

---@type AvanteLLMToolFunc<{ abs_path: string }>
function M.read_global_file(opts, on_log)
  local abs_path = Helpers.get_abs_path(opts.abs_path)
  if Helpers.is_ignored(abs_path) then return "", "This file is ignored: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  local file = io.open(abs_path, "r")
  if not file then return "", "file not found: " .. abs_path end
  local content = file:read("*a")
  file:close()
  return content, nil
end

---@type AvanteLLMToolFunc<{ abs_path: string, content: string }>
function M.write_global_file(opts, on_log, on_complete)
  local abs_path = Helpers.get_abs_path(opts.abs_path)
  if Helpers.is_ignored(abs_path) then return false, "This file is ignored: " .. abs_path end
  if on_log then on_log("path: " .. abs_path) end
  if on_log then on_log("content: " .. opts.content) end
  if not on_complete then return false, "on_complete not provided" end
  Helpers.confirm("Are you sure you want to write to the file: " .. abs_path, function(ok)
    if not ok then
      on_complete(false, "User canceled")
      return
    end
    local file = io.open(abs_path, "w")
    if not file then
      on_complete(false, "file not found: " .. abs_path)
      return
    end
    file:write(opts.content)
    file:close()
    on_complete(true, nil)
  end)
end

---@type AvanteLLMToolFunc<{ rel_path: string, new_rel_path: string }>
function M.rename_file(opts, on_log, on_complete)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
  if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
  local new_abs_path = Helpers.get_abs_path(opts.new_rel_path)
  if on_log then on_log(abs_path .. " -> " .. new_abs_path) end
  if not Helpers.has_permission_to_access(new_abs_path) then
    return false, "No permission to access path: " .. new_abs_path
  end
  if Path:new(new_abs_path):exists() then return false, "File already exists: " .. new_abs_path end
  if not on_complete then return false, "on_complete not provided" end
  Helpers.confirm(
    "Are you sure you want to rename the file: " .. abs_path .. " to: " .. new_abs_path,
    function(ok, reason)
      if not ok then
        on_complete(false, "User declined, reason: " .. (reason or "unknown"))
        return
      end
      os.rename(abs_path, new_abs_path)
      on_complete(true, nil)
    end
  )
end

---@type AvanteLLMToolFunc<{ rel_path: string, new_rel_path: string }>
function M.copy_file(opts, on_log)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
  if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
  local new_abs_path = Helpers.get_abs_path(opts.new_rel_path)
  if not Helpers.has_permission_to_access(new_abs_path) then
    return false, "No permission to access path: " .. new_abs_path
  end
  if Path:new(new_abs_path):exists() then return false, "File already exists: " .. new_abs_path end
  if on_log then on_log("Copying file: " .. abs_path .. " to " .. new_abs_path) end
  Path:new(new_abs_path):write(Path:new(abs_path):read())
  return true, nil
end

---@type AvanteLLMToolFunc<{ rel_path: string }>
function M.delete_file(opts, on_log, on_complete)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
  if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
  if not on_complete then return false, "on_complete not provided" end
  Helpers.confirm("Are you sure you want to delete the file: " .. abs_path, function(ok, reason)
    if not ok then
      on_complete(false, "User declined, reason: " .. (reason or "unknown"))
      return
    end
    if on_log then on_log("Deleting file: " .. abs_path) end
    os.remove(abs_path)
    on_complete(true, nil)
  end)
end

---@type AvanteLLMToolFunc<{ rel_path: string }>
function M.create_dir(opts, on_log, on_complete)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if Path:new(abs_path):exists() then return false, "Directory already exists: " .. abs_path end
  if not on_complete then return false, "on_complete not provided" end
  Helpers.confirm("Are you sure you want to create the directory: " .. abs_path, function(ok, reason)
    if not ok then
      on_complete(false, "User declined, reason: " .. (reason or "unknown"))
      return
    end
    if on_log then on_log("Creating directory: " .. abs_path) end
    Path:new(abs_path):mkdir({ parents = true })
    on_complete(true, nil)
  end)
end

---@type AvanteLLMToolFunc<{ rel_path: string, new_rel_path: string }>
function M.rename_dir(opts, on_log, on_complete)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "Directory not found: " .. abs_path end
  if not Path:new(abs_path):is_dir() then return false, "Path is not a directory: " .. abs_path end
  local new_abs_path = Helpers.get_abs_path(opts.new_rel_path)
  if not Helpers.has_permission_to_access(new_abs_path) then
    return false, "No permission to access path: " .. new_abs_path
  end
  if Path:new(new_abs_path):exists() then return false, "Directory already exists: " .. new_abs_path end
  if not on_complete then return false, "on_complete not provided" end
  Helpers.confirm(
    "Are you sure you want to rename directory " .. abs_path .. " to " .. new_abs_path .. "?",
    function(ok, reason)
      if not ok then
        on_complete(false, "User declined, reason: " .. (reason or "unknown"))
        return
      end
      if on_log then on_log("Renaming directory: " .. abs_path .. " to " .. new_abs_path) end
      os.rename(abs_path, new_abs_path)
      on_complete(true, nil)
    end
  )
end

---@type AvanteLLMToolFunc<{ rel_path: string }>
function M.delete_dir(opts, on_log, on_complete)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return false, "Directory not found: " .. abs_path end
  if not Path:new(abs_path):is_dir() then return false, "Path is not a directory: " .. abs_path end
  if not on_complete then return false, "on_complete not provided" end
  Helpers.confirm("Are you sure you want to delete the directory: " .. abs_path, function(ok, reason)
    if not ok then
      on_complete(false, "User declined, reason: " .. (reason or "unknown"))
      return
    end
    if on_log then on_log("Deleting directory: " .. abs_path) end
    os.remove(abs_path)
    on_complete(true, nil)
  end)
end

---@type AvanteLLMToolFunc<{ query: string }>
function M.web_search(opts, on_log)
  local provider_type = Config.web_search_engine.provider
  local proxy = Config.web_search_engine.proxy
  if provider_type == nil then return nil, "Search engine provider is not set" end
  if on_log then on_log("provider: " .. provider_type) end
  if on_log then on_log("query: " .. opts.query) end
  local search_engine = Config.web_search_engine.providers[provider_type]
  if search_engine == nil then return nil, "No search engine found: " .. provider_type end
  if provider_type ~= "searxng" and search_engine.api_key_name == "" then return nil, "No API key provided" end
  local api_key = provider_type ~= "searxng" and Utils.environment.parse(search_engine.api_key_name) or nil
  if provider_type ~= "searxng" and api_key == nil or api_key == "" then
    return nil, "Environment variable " .. search_engine.api_key_name .. " is not set"
  end
  if provider_type == "tavily" then
    local curl_opts = {
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
      },
      body = vim.json.encode(vim.tbl_deep_extend("force", {
        query = opts.query,
      }, search_engine.extra_request_body)),
    }
    if proxy then curl_opts.proxy = proxy end
    local resp = curl.post("https://api.tavily.com/search", curl_opts)
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
    local curl_opts = {
      headers = {
        ["Content-Type"] = "application/json",
      },
    }
    if proxy then curl_opts.proxy = proxy end
    local resp = curl.get("https://serpapi.com/search?" .. query_string, curl_opts)
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
    local curl_opts = {
      headers = {
        ["Content-Type"] = "application/json",
      },
    }
    if proxy then curl_opts.proxy = proxy end
    local resp = curl.get("https://searchapi.io/api/v1/search?" .. query_string, curl_opts)
    if resp.status ~= 200 then return nil, "Error: " .. resp.body end
    local jsn = vim.json.decode(resp.body)
    return search_engine.format_response_body(jsn)
  elseif provider_type == "google" then
    local engine_id = Utils.environment.parse(search_engine.engine_id_name)
    if engine_id == nil or engine_id == "" then
      return nil, "Environment variable " .. search_engine.engine_id_name .. " is not set"
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
    local curl_opts = {
      headers = {
        ["Content-Type"] = "application/json",
      },
    }
    if proxy then curl_opts.proxy = proxy end
    local resp = curl.get("https://www.googleapis.com/customsearch/v1?" .. query_string, curl_opts)
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
    local curl_opts = {
      headers = {
        ["Authorization"] = "Bot " .. api_key,
        ["Content-Type"] = "application/json",
      },
    }
    if proxy then curl_opts.proxy = proxy end
    local resp = curl.get("https://kagi.com/api/v0/search?" .. query_string, curl_opts)
    if resp.status ~= 200 then return nil, "Error: " .. resp.body end
    local jsn = vim.json.decode(resp.body)
    return search_engine.format_response_body(jsn)
  elseif provider_type == "brave" then
    local query_params = vim.tbl_deep_extend("force", {
      q = opts.query,
    }, search_engine.extra_request_body)
    local query_string = ""
    for key, value in pairs(query_params) do
      query_string = query_string .. key .. "=" .. vim.uri_encode(value) .. "&"
    end
    local curl_opts = {
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Subscription-Token"] = api_key,
      },
    }
    if proxy then curl_opts.proxy = proxy end
    local resp = curl.get("https://api.search.brave.com/res/v1/web/search?" .. query_string, curl_opts)
    if resp.status ~= 200 then return nil, "Error: " .. resp.body end
    local jsn = vim.json.decode(resp.body)
    return search_engine.format_response_body(jsn)
  elseif provider_type == "searxng" then
    local searxng_api_url = Utils.environment.parse(search_engine.api_url_name)
    if searxng_api_url == nil or searxng_api_url == "" then
      return nil, "Environment variable " .. search_engine.api_url_name .. " is not set"
    end
    local query_params = vim.tbl_deep_extend("force", {
      q = opts.query,
    }, search_engine.extra_request_body)
    local query_string = ""
    for key, value in pairs(query_params) do
      query_string = query_string .. key .. "=" .. vim.uri_encode(value) .. "&"
    end
    local resp = curl.get(searxng_api_url .. "?" .. query_string, {
      headers = {
        ["Content-Type"] = "application/json",
      },
    })
    if resp.status ~= 200 then return nil, "Error: " .. resp.body end
    local jsn = vim.json.decode(resp.body)
    return search_engine.format_response_body(jsn)
  end
  return nil, "Error: No search engine found"
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
function M.git_commit(opts, on_log, on_complete)
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
  commit_msg_lines[#commit_msg_lines + 1] = ""
  if git_user ~= "" and git_email ~= "" then
    commit_msg_lines[#commit_msg_lines + 1] = string.format("Signed-off-by: %s <%s>", git_user, git_email)
  end

  -- Construct full commit message for confirmation
  local full_commit_msg = table.concat(commit_msg_lines, "\n")

  if not on_complete then return false, "on_complete not provided" end

  -- Confirm with user
  Helpers.confirm("Are you sure you want to commit with message:\n" .. full_commit_msg, function(ok, reason)
    if not ok then
      on_complete(false, "User declined, reason: " .. (reason or "unknown"))
      return
    end
    -- Stage changes if scope is provided
    if opts.scope then
      local stage_cmd = string.format("git add %s", opts.scope)
      if on_log then on_log("Staging files: " .. stage_cmd) end
      local stage_result = vim.fn.system(stage_cmd)
      if vim.v.shell_error ~= 0 then
        on_complete(false, "Failed to stage files: " .. stage_result)
        return
      end
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

    if vim.v.shell_error ~= 0 then
      on_complete(false, "Failed to commit: " .. result)
      return
    end

    on_complete(true, nil)
  end)
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
function M.python(opts, on_log, on_complete)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return nil, "No permission to access path: " .. abs_path end
  if not Path:new(abs_path):exists() then return nil, "Path not found: " .. abs_path end
  if on_log then on_log("cwd: " .. abs_path) end
  if on_log then on_log("code:\n" .. opts.code) end
  local container_image = opts.container_image or "python:3.11-slim-bookworm"
  if not on_complete then return nil, "on_complete not provided" end
  Helpers.confirm(
    "Are you sure you want to run the following python code in the `"
      .. container_image
      .. "` container, in the directory: `"
      .. abs_path
      .. "`?\n"
      .. opts.code,
    function(ok, reason)
      if not ok then
        on_complete(nil, "User declined, reason: " .. (reason or "unknown"))
        return
      end
      if vim.fn.executable("docker") == 0 then
        on_complete(nil, "Python tool is not available to execute any code")
        return
      end

      local function handle_result(result) ---@param result vim.SystemCompleted
        if result.code ~= 0 then return nil, "Error: " .. (result.stderr or "Unknown error") end

        Utils.debug("output", result.stdout)
        return result.stdout, nil
      end
      vim.system(
        {
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
        },
        {
          text = true,
          cwd = abs_path,
        },
        vim.schedule_wrap(function(result)
          if not on_complete then return end
          local output, err = handle_result(result)
          on_complete(output, err)
        end)
      )
    end
  )
end

---@param user_input string
---@param history_messages AvanteLLMMessage[]
---@return AvanteLLMTool[]
function M.get_tools(user_input, history_messages)
  local custom_tools = Config.custom_tools
  if type(custom_tools) == "function" then custom_tools = custom_tools() end
  ---@type AvanteLLMTool[]
  local unfiltered_tools = vim.list_extend(vim.list_extend({}, M._tools), custom_tools)
  return vim
    .iter(unfiltered_tools)
    :filter(function(tool) ---@param tool AvanteLLMTool
      -- Always disable tools that are explicitly disabled
      if vim.tbl_contains(Config.disabled_tools, tool.name) then return false end
      if tool.enabled == nil then
        return true
      else
        return tool.enabled({ user_input = user_input, history_messages = history_messages })
      end
    end)
    :totable()
end

---@type AvanteLLMTool[]
M._tools = {
  require("avante.llm_tools.replace_in_file"),
  require("avante.llm_tools.dispatch_agent"),
  require("avante.llm_tools.glob"),
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
    name = "run_python",
    description = "Run python code in current project scope. Can't use it to read files or modify files.",
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
          description = "Relative path to the project directory, as cwd",
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
    description = "Get git diff for generating commit message in current project scope",
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
    description = "Commit changes with the given commit message in current project scope",
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
  require("avante.llm_tools.ls"),
  require("avante.llm_tools.grep"),
  {
    name = "read_file_toplevel_symbols",
    description = "Read the top-level symbols of a file in current project scope",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the file in current project scope",
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
  require("avante.llm_tools.str_replace"),
  require("avante.llm_tools.view"),
  require("avante.llm_tools.create"),
  require("avante.llm_tools.insert"),
  require("avante.llm_tools.undo_edit"),
  {
    name = "read_global_file",
    description = "Read the contents of a file in the global scope. If the file content is already in the context, do not use this tool.",
    enabled = function(opts)
      if opts.user_input:match("@read_global_file") then return true end
      for _, message in ipairs(opts.history_messages) do
        if message.role == "user" then
          local content = message.content
          if type(content) == "string" and content:match("@read_global_file") then return true end
          if type(content) == "table" then
            for _, item in ipairs(content) do
              if type(item) == "string" and item:match("@read_global_file") then return true end
            end
          end
        end
      end
      return false
    end,
    param = {
      type = "table",
      fields = {
        {
          name = "abs_path",
          description = "Absolute path to the file in global scope",
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
    name = "write_global_file",
    description = "Write to a file in the global scope",
    enabled = function(opts)
      if opts.user_input:match("@write_global_file") then return true end
      for _, message in ipairs(opts.history_messages) do
        if message.role == "user" then
          local content = message.content
          if type(content) == "string" and content:match("@write_global_file") then return true end
          if type(content) == "table" then
            for _, item in ipairs(content) do
              if type(item) == "string" and item:match("@write_global_file") then return true end
            end
          end
        end
      end
      return false
    end,
    param = {
      type = "table",
      fields = {
        {
          name = "abs_path",
          description = "Absolute path to the file in global scope",
          type = "string",
        },
        {
          name = "content",
          description = "Content to write to the file",
          type = "string",
        },
      },
    },
    returns = {
      {
        name = "success",
        description = "True if the file was written successfully, false otherwise",
        type = "boolean",
      },
      {
        name = "error",
        description = "Error message if the file was not written successfully",
        type = "string",
        optional = true,
      },
    },
  },
  {
    name = "rename_file",
    description = "Rename a file in current project scope",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the file in current project scope",
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
    description = "Delete a file in current project scope",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the file in current project scope",
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
    description = "Create a new directory in current project scope",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the project directory",
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
    description = "Rename a directory in current project scope",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the project directory",
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
    description = "Delete a directory in current project scope",
    param = {
      type = "table",
      fields = {
        {
          name = "rel_path",
          description = "Relative path to the project directory",
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
  require("avante.llm_tools.bash"),
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
  {
    name = "read_definitions",
    description = "Retrieves the complete source code definitions of any symbol (function, type, constant, etc.) from your codebase.",
    param = {
      type = "table",
      fields = {
        {
          name = "symbol_name",
          description = "The name of the symbol to retrieve the definition for",
          type = "string",
        },
        {
          name = "show_line_numbers",
          description = "Whether to show line numbers in the definitions",
          type = "boolean",
          default = false,
        },
      },
    },
    returns = {
      {
        name = "definitions",
        description = "The source code definitions of the symbol",
        type = "string[]",
      },
      {
        name = "error",
        description = "Error message if the definition retrieval failed",
        type = "string",
        optional = true,
      },
    },
    func = function(input_json, on_log, on_complete)
      local symbol_name = input_json.symbol_name
      local show_line_numbers = input_json.show_line_numbers
      if on_log then on_log("symbol_name: " .. vim.inspect(symbol_name)) end
      if on_log then on_log("show_line_numbers: " .. vim.inspect(show_line_numbers)) end
      if not symbol_name then return nil, "No symbol name provided" end
      local sidebar = require("avante").get()
      if not sidebar then return nil, "No sidebar" end
      local bufnr = sidebar.code.bufnr
      if not bufnr then return nil, "No bufnr" end
      if not vim.api.nvim_buf_is_valid(bufnr) then return nil, "Invalid bufnr" end
      if on_log then on_log("bufnr: " .. vim.inspect(bufnr)) end
      Utils.lsp.read_definitions(bufnr, symbol_name, show_line_numbers, function(definitions, error)
        local encoded_defs = vim.json.encode(definitions)
        on_complete(encoded_defs, error)
      end)
      return nil, nil
    end,
  },
}

--- compatibility alias for old calls & tests
M.run_python = M.python

---@param tools AvanteLLMTool[]
---@param tool_use AvanteLLMToolUse
---@param on_log? fun(tool_id: string, tool_name: string, log: string, state: AvanteLLMToolUseState): nil
---@param on_complete? fun(result: string | nil, error: string | nil): nil
---@param session_ctx? table
---@return string | nil result
---@return string | nil error
function M.process_tool_use(tools, tool_use, on_log, on_complete, session_ctx)
  -- Utils.debug("use tool", tool_use.name, tool_use.input_json)

  -- Check if execution is already cancelled
  if Helpers.is_cancelled then
    Utils.debug("Tool execution cancelled before starting: " .. tool_use.name)
    if on_complete then
      on_complete(nil, Helpers.CANCEL_TOKEN)
      return
    end
    return nil, Helpers.CANCEL_TOKEN
  end

  local func
  if tool_use.name == "str_replace_editor" then
    func = M.str_replace_editor
  else
    ---@type AvanteLLMTool?
    local tool = vim.iter(tools):find(function(tool) return tool.name == tool_use.name end) ---@param tool AvanteLLMTool
    if tool == nil then return nil, "This tool is not provided: " .. tool_use.name end
    func = tool.func or M[tool.name]
  end
  local input_json = tool_use.input
  if not func then return nil, "Tool not found: " .. tool_use.name end
  if on_log then on_log(tool_use.id, tool_use.name, "running tool", "running") end

  -- Set up a timer to periodically check for cancellation
  local cancel_timer
  if on_complete then
    cancel_timer = vim.loop.new_timer()
    if cancel_timer then
      cancel_timer:start(
        100,
        100,
        vim.schedule_wrap(function()
          if Helpers.is_cancelled then
            Utils.debug("Tool execution cancelled during execution: " .. tool_use.name)
            if cancel_timer and not cancel_timer:is_closing() then
              cancel_timer:stop()
              cancel_timer:close()
            end
            Helpers.is_cancelled = false
            on_complete(nil, Helpers.CANCEL_TOKEN)
          end
        end)
      )
    end
  end

  ---@param result string | nil | boolean
  ---@param err string | nil
  local function handle_result(result, err)
    -- Stop the cancellation timer if it exists
    if cancel_timer and not cancel_timer:is_closing() then
      cancel_timer:stop()
      cancel_timer:close()
    end

    -- Check for cancellation one more time before processing result
    if Helpers.is_cancelled then
      if on_log then on_log(tool_use.id, tool_use.name, "cancelled during result handling", "failed") end
      return nil, Helpers.CANCEL_TOKEN
    end

    if err ~= nil then
      if on_log then on_log(tool_use.id, tool_use.name, "Error: " .. err, "failed") end
    else
      if on_log then on_log(tool_use.id, tool_use.name, "tool finished", "succeeded") end
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
    -- Check for cancellation during logging
    if Helpers.is_cancelled then return end
    if on_log then on_log(tool_use.id, tool_use.name, log, "running") end
  end, function(result, err)
    -- Check for cancellation before completing
    if Helpers.is_cancelled then
      Helpers.is_cancelled = false
      if on_complete then on_complete(nil, Helpers.CANCEL_TOKEN) end
      return
    end

    result, err = handle_result(result, err)
    if on_complete == nil then
      Utils.error("asynchronous tool " .. tool_use.name .. " result not handled")
      return
    end
    on_complete(result, err)
  end, session_ctx)

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
