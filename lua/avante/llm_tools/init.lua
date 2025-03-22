local curl = require("plenary.curl")
local Utils = require("avante.utils")
local Path = require("plenary.path")
local Config = require("avante.config")
local RagService = require("avante.rag_service")
local Diff = require("avante.diff")
local Highlights = require("avante.highlights")
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

---@type AvanteLLMToolFunc<{ command: "view" | "str_replace" | "create" | "insert" | "undo_edit", path: string, old_str?: string, new_str?: string, file_text?: string, insert_line?: integer, new_str?: string }>
function M.str_replace_editor(opts, on_log, on_complete)
  if on_log then on_log("command: " .. opts.command) end
  if on_log then on_log("path: " .. vim.inspect(opts.path)) end
  if not on_complete then return false, "on_complete not provided" end
  local abs_path = Helpers.get_abs_path(opts.path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
  local sidebar = require("avante").get()
  if not sidebar then return false, "Avante sidebar not found" end
  local get_bufnr = function()
    local current_winid = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(sidebar.code.winid)
    local bufnr = Utils.get_or_create_buffer_with_filepath(abs_path)
    vim.api.nvim_set_current_win(current_winid)
    return bufnr
  end
  if opts.command == "view" then
    if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
    if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
    local file = io.open(abs_path, "r")
    if not file then return false, "file not found: " .. abs_path end
    local lines = Utils.read_file_from_buf_or_disk(abs_path)
    local content = lines and table.concat(lines, "\n") or ""
    on_complete(content, nil)
    return
  end
  if opts.command == "str_replace" then
    if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
    if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
    local file = io.open(abs_path, "r")
    if not file then return false, "file not found: " .. abs_path end
    if opts.old_str == nil then return false, "old_str not provided" end
    if opts.new_str == nil then return false, "new_str not provided" end
    local bufnr = get_bufnr()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local lines_content = table.concat(lines, "\n")
    local old_lines = vim.split(opts.old_str, "\n")
    local new_lines = vim.split(opts.new_str, "\n")
    local start_line, end_line
    for i = 1, #lines - #old_lines + 1 do
      local match = true
      for j = 1, #old_lines do
        if lines[i + j - 1] ~= old_lines[j] then
          match = false
          break
        end
      end
      if match then
        start_line = i
        end_line = i + #old_lines - 1
        break
      end
    end
    if start_line == nil or end_line == nil then
      on_complete(false, "Failed to find the old string: " .. opts.old_str)
      return
    end
    ---@diagnostic disable-next-line: assign-type-mismatch, missing-fields
    local patch = vim.diff(opts.old_str, opts.new_str, { ---@type integer[][]
      algorithm = "histogram",
      result_type = "indices",
      ctxlen = vim.o.scrolloff,
    })
    local patch_start_line_content = "<<<<<<< HEAD"
    local patch_end_line_content = ">>>>>>> new "
    --- add random characters to the end of the line to avoid conflicts
    patch_end_line_content = patch_end_line_content .. Utils.random_string(10)
    local current_start_a = 1
    local patched_new_lines = {}
    for _, hunk in ipairs(patch) do
      local start_a, count_a, start_b, count_b = unpack(hunk)
      if current_start_a < start_a then
        vim.list_extend(patched_new_lines, vim.list_slice(old_lines, current_start_a, start_a - 1))
      end
      table.insert(patched_new_lines, patch_start_line_content)
      vim.list_extend(patched_new_lines, vim.list_slice(old_lines, start_a, start_a + count_a - 1))
      table.insert(patched_new_lines, "=======")
      vim.list_extend(patched_new_lines, vim.list_slice(new_lines, start_b, start_b + count_b - 1))
      table.insert(patched_new_lines, patch_end_line_content)
      current_start_a = start_a + count_a
    end
    if current_start_a <= #old_lines then
      vim.list_extend(patched_new_lines, vim.list_slice(old_lines, current_start_a, #old_lines))
    end
    vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, patched_new_lines)
    local current_winid = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(sidebar.code.winid)
    Diff.add_visited_buffer(bufnr)
    Diff.process(bufnr)
    if #patch > 0 then
      vim.api.nvim_win_set_cursor(sidebar.code.winid, { math.max(patch[1][1] + start_line - 1, 1), 0 })
    end
    vim.cmd("normal! zz")
    vim.api.nvim_set_current_win(current_winid)
    local augroup = vim.api.nvim_create_augroup("avante_str_replace_editor", { clear = true })
    local confirm = Helpers.confirm("Are you sure you want to apply this modification?", function(ok)
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
      vim.api.nvim_set_current_win(sidebar.code.winid)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
      vim.cmd("undo")
      if not ok then
        vim.api.nvim_set_current_win(current_winid)
        on_complete(false, "User canceled")
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, new_lines)
      vim.api.nvim_set_current_win(current_winid)
      on_complete(true, nil)
    end, { focus = false })
    vim.api.nvim_set_current_win(sidebar.code.winid)
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
      group = augroup,
      buffer = bufnr,
      callback = function()
        local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local current_lines_content = table.concat(current_lines, "\n")
        if current_lines_content:find(patch_end_line_content) then return end
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
        if confirm then confirm:close() end
        if vim.api.nvim_win_is_valid(current_winid) then vim.api.nvim_set_current_win(current_winid) end
        if lines_content == current_lines_content then
          on_complete(false, "User canceled")
          return
        end
        on_complete(true, nil)
      end,
    })
    return
  end
  if opts.command == "create" then
    if opts.file_text == nil then return false, "file_text not provided" end
    if Path:new(abs_path):exists() then return false, "File already exists: " .. abs_path end
    local lines = vim.split(opts.file_text, "\n")
    local bufnr = get_bufnr()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    Helpers.confirm("Are you sure you want to create this file?", function(ok)
      if not ok then
        -- close the buffer
        vim.api.nvim_buf_delete(bufnr, { force = true })
        on_complete(false, "User canceled")
        return
      end
      -- save the file
      local current_winid = vim.api.nvim_get_current_win()
      local winid = Utils.get_winid(bufnr)
      vim.api.nvim_set_current_win(winid)
      vim.cmd("write")
      vim.api.nvim_set_current_win(current_winid)
      on_complete(true, nil)
    end)
    return
  end
  if opts.command == "insert" then
    if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
    if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
    if opts.insert_line == nil then return false, "insert_line not provided" end
    if opts.new_str == nil then return false, "new_str not provided" end
    local ns_id = vim.api.nvim_create_namespace("avante_insert_diff")
    local bufnr = get_bufnr()
    local function clear_highlights() vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1) end
    local new_lines = vim.split(opts.new_str, "\n")
    local max_col = vim.o.columns
    local virt_lines = vim
      .iter(new_lines)
      :map(function(line)
        --- append spaces to the end of the line
        local line_ = line .. string.rep(" ", max_col - #line)
        return { { line_, Highlights.INCOMING } }
      end)
      :totable()
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, opts.insert_line - 1, 0, {
      virt_lines = virt_lines,
      hl_eol = true,
      hl_mode = "combine",
    })
    Helpers.confirm("Are you sure you want to insert these lines?", function(ok)
      clear_highlights()
      if not ok then
        on_complete(false, "User canceled")
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, opts.insert_line - 1, opts.insert_line - 1, false, new_lines)
      on_complete(true, nil)
    end)
    return
  end
  if opts.command == "undo_edit" then
    if not Path:new(abs_path):exists() then return false, "File not found: " .. abs_path end
    if not Path:new(abs_path):is_file() then return false, "Path is not a file: " .. abs_path end
    local bufnr = get_bufnr()
    Helpers.confirm("Are you sure you want to undo edit this file?", function(ok)
      if not ok then
        on_complete(false, "User canceled")
        return
      end
      local current_winid = vim.api.nvim_get_current_win()
      local winid = Utils.get_winid(bufnr)
      vim.api.nvim_set_current_win(winid)
      -- run undo
      vim.cmd("undo")
      vim.api.nvim_set_current_win(current_winid)
      on_complete(true, nil)
    end)
    return
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

---@type AvanteLLMToolFunc<{ rel_path: string }>
function M.create_file(opts, on_log)
  local abs_path = Helpers.get_abs_path(opts.rel_path)
  if not Helpers.has_permission_to_access(abs_path) then return false, "No permission to access path: " .. abs_path end
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
  Helpers.confirm("Are you sure you want to rename the file: " .. abs_path .. " to: " .. new_abs_path, function(ok)
    if not ok then
      on_complete(false, "User canceled")
      return
    end
    os.rename(abs_path, new_abs_path)
    on_complete(true, nil)
  end)
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
  Helpers.confirm("Are you sure you want to delete the file: " .. abs_path, function(ok)
    if not ok then
      on_complete(false, "User canceled")
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
  Helpers.confirm("Are you sure you want to create the directory: " .. abs_path, function(ok)
    if not ok then
      on_complete(false, "User canceled")
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
    function(ok)
      if not ok then
        on_complete(false, "User canceled")
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
  Helpers.confirm("Are you sure you want to delete the directory: " .. abs_path, function(ok)
    if not ok then
      on_complete(false, "User canceled")
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
  if provider_type == nil then return nil, "Search engine provider is not set" end
  if on_log then on_log("provider: " .. provider_type) end
  if on_log then on_log("query: " .. opts.query) end
  local search_engine = Config.web_search_engine.providers[provider_type]
  if search_engine == nil then return nil, "No search engine found: " .. provider_type end
  if search_engine.api_key_name == "" then return nil, "No API key provided" end
  local api_key = Utils.environment.parse(search_engine.api_key_name)
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
  elseif provider_type == "brave" then
    local query_params = vim.tbl_deep_extend("force", {
      q = opts.query,
    }, search_engine.extra_request_body)
    local query_string = ""
    for key, value in pairs(query_params) do
      query_string = query_string .. key .. "=" .. vim.uri_encode(value) .. "&"
    end
    local resp = curl.get("https://api.search.brave.com/res/v1/web/search?" .. query_string, {
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Subscription-Token"] = api_key,
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
  commit_msg_lines[#commit_msg_lines + 1] = "🤖 Generated with [avante.nvim](https://github.com/yetone/avante.nvim)"
  commit_msg_lines[#commit_msg_lines + 1] = "Co-Authored-By: avante.nvim <noreply-avante@yetone.ai>"
  if git_user ~= "" and git_email ~= "" then
    commit_msg_lines[#commit_msg_lines + 1] = string.format("Signed-off-by: %s <%s>", git_user, git_email)
  end

  -- Construct full commit message for confirmation
  local full_commit_msg = table.concat(commit_msg_lines, "\n")

  if not on_complete then return false, "on_complete not provided" end

  -- Confirm with user
  Helpers.confirm("Are you sure you want to commit with message:\n" .. full_commit_msg, function(ok)
    if not ok then
      on_complete(false, "User canceled")
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
    function(ok)
      if not ok then
        on_complete(nil, "User canceled")
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
    name = "python",
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
  require("avante.llm_tools.read_file"),
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
    name = "create_file",
    description = "Create a new file in current project scope",
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

---@param tools AvanteLLMTool[]
---@param tool_use AvanteLLMToolUse
---@param on_log? fun(tool_name: string, log: string): nil
---@param on_complete? fun(result: string | nil, error: string | nil): nil
---@return string | nil result
---@return string | nil error
function M.process_tool_use(tools, tool_use, on_log, on_complete)
  Utils.debug("use tool", tool_use.name, tool_use.input_json)

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
  local input_json = vim.json.decode(tool_use.input_json)
  if not func then return nil, "Tool not found: " .. tool_use.name end
  if on_log then on_log(tool_use.name, "running tool") end

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
      if on_log then on_log(tool_use.name, "cancelled during result handling") end
      return nil, Helpers.CANCEL_TOKEN
    end

    if on_log then on_log(tool_use.name, "tool finished") end
    -- Utils.debug("result", result)
    -- Utils.debug("error", error)
    if err ~= nil then
      if on_log then on_log(tool_use.name, "Error: " .. err) end
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
    if on_log then on_log(tool_use.name, log) end
  end, function(result, err)
    -- Check for cancellation before completing
    if Helpers.is_cancelled then
      if on_complete then on_complete(nil, Helpers.CANCEL_TOKEN) end
      return
    end

    result, err = handle_result(result, err)
    if on_complete == nil then
      Utils.error("asynchronous tool " .. tool_use.name .. " result not handled")
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
