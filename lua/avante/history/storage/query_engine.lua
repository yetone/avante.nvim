---🔍 Query Engine for Avante history storage
---Provides search and filtering capabilities across chat histories

local Utils = require("avante.utils")

local M = {}

---@class avante.storage.QueryEngine
---@field config table Query engine configuration
---@field storage_engine table Storage engine instance
local QueryEngine = {}
QueryEngine.__index = QueryEngine

---🏗️ Create new query engine instance
---@param storage_engine table Storage engine to query against
---@param config? table Query configuration
---@return avante.storage.QueryEngine
function M.new(storage_engine, config)
  config = config or {}
  
  local default_config = {
    max_results = config.max_results or 100, -- 📊 Maximum results to return
    search_debounce_ms = config.search_debounce_ms or 200, -- ⏰ Debounce search queries
    case_sensitive = config.case_sensitive or false, -- 🔤 Case sensitivity for text search
    fuzzy_search = config.fuzzy_search or true, -- 🔍 Enable fuzzy matching
    highlight_matches = config.highlight_matches or true, -- 🎨 Highlight search matches
    index_content = config.index_content ~= false, -- 📝 Index message content
    index_tool_calls = config.index_tool_calls ~= false, -- 🛠️ Index tool invocations
  }
  
  local instance = {
    config = default_config,
    storage_engine = storage_engine,
    _search_cache = {}, -- 💾 Cache for search results
    _search_debounce_timers = {}, -- ⏰ Debounce timers for search queries
  }
  
  return setmetatable(instance, QueryEngine)
end

---@class avante.storage.SearchQuery
---@field text? string Text to search for in message content
---@field role? "user" | "assistant" Filter by message role
---@field date_range? { from: string, to: string } Filter by date range (ISO timestamps)
---@field tool_names? string[] Filter by tool names used
---@field provider? string Filter by LLM provider
---@field model? string Filter by model name
---@field has_tools? boolean Filter messages that include tool calls
---@field has_errors? boolean Filter messages with tool execution errors
---@field message_count_range? { min: number, max: number } Filter by conversation length
---@field content_size_range? { min: number, max: number } Filter by content size
---@field tags? string[] Filter by custom tags (if supported)
---@field project_name? string Limit search to specific project

---@class avante.storage.SearchOptions
---@field limit? number Maximum results to return
---@field offset? number Offset for pagination
---@field sort_by? "relevance" | "date" | "size" | "message_count" Sort criteria
---@field sort_order? "asc" | "desc" Sort order
---@field include_content? boolean Include full message content in results
---@field highlight_matches? boolean Highlight search matches in results

---@class avante.storage.SearchResult
---@field score number Relevance score (0-1)
---@field history_uuid string UUID of the matching history
---@field project_name string Project name
---@field metadata table History metadata
---@field matches table[] Individual message matches within the history
---@field snippet? string Text snippet showing the match context
---@field highlighted_snippet? string Snippet with highlighted matches

---🔍 Perform text search across history content
---@param query avante.storage.SearchQuery
---@param opts? avante.storage.SearchOptions
---@return avante.storage.SearchResult[]
---@return string? error_message
function QueryEngine:search(query, opts)
  opts = opts or {}
  
  -- 📊 Apply default options
  local search_opts = vim.tbl_deep_extend("force", {
    limit = self.config.max_results,
    offset = 0,
    sort_by = "relevance",
    sort_order = "desc",
    include_content = false,
    highlight_matches = self.config.highlight_matches,
  }, opts)
  
  -- 💾 Check cache for recent identical queries
  local cache_key = self:_get_search_cache_key(query, search_opts)
  local cached_result = self._search_cache[cache_key]
  if cached_result and (os.time() - cached_result.timestamp) < 60 then -- 📅 1 minute cache
    return cached_result.results, nil
  end
  
  local results = {}
  
  -- 🔍 Determine projects to search
  local projects_to_search = {}
  if query.project_name then
    projects_to_search = { query.project_name }
  else
    -- 📁 Get all projects (this would need to be implemented in storage engine)
    local all_projects, error = self:_get_all_projects()
    if error then
      return {}, "Failed to get projects: " .. error
    end
    projects_to_search = all_projects
  end
  
  -- 🔍 Search each project
  for _, project_name in ipairs(projects_to_search) do
    local project_results, project_error = self:_search_project(project_name, query, search_opts)
    if project_error then
      Utils.warn("Error searching project " .. project_name .. ": " .. project_error)
    else
      for _, result in ipairs(project_results) do
        table.insert(results, result)
      end
    end
  end
  
  -- 📊 Sort results
  self:_sort_search_results(results, search_opts.sort_by, search_opts.sort_order)
  
  -- 📑 Apply pagination
  local paginated_results = self:_paginate_results(results, search_opts.limit, search_opts.offset)
  
  -- 💾 Cache results
  self._search_cache[cache_key] = {
    results = paginated_results,
    timestamp = os.time(),
  }
  
  return paginated_results, nil
end

---🔍 Search within a specific project
---@param project_name string
---@param query avante.storage.SearchQuery
---@param opts avante.storage.SearchOptions
---@return avante.storage.SearchResult[]
---@return string? error_message
function QueryEngine:_search_project(project_name, query, opts)
  -- 📋 Get all histories for the project
  local histories, list_error = self.storage_engine:list(project_name)
  if list_error then
    return {}, list_error
  end
  
  local project_results = {}
  
  for _, history_info in ipairs(histories) do
    -- 📊 Apply metadata filters first (before loading full history)
    if not self:_matches_metadata_filters(history_info, query) then
      goto continue
    end
    
    -- 📖 Load full history if needed for content search
    local history, load_error
    if query.text or query.tool_names or query.has_tools or query.has_errors or opts.include_content then
      history, load_error = self.storage_engine:load(history_info.uuid, project_name)
      if load_error then
        Utils.warn("Failed to load history " .. history_info.uuid .. ": " .. load_error)
        goto continue
      end
    end
    
    -- 🔍 Search history content
    local matches = {}
    if history then
      matches = self:_search_history_content(history, query)
    end
    
    -- 📊 Calculate relevance score
    local score = self:_calculate_relevance_score(history_info, history, matches, query)
    
    -- ✅ Include result if it has matches or passes filters
    if #matches > 0 or score > 0 then
      local result = {
        score = score,
        history_uuid = history_info.uuid,
        project_name = project_name,
        metadata = history_info,
        matches = matches,
      }
      
      -- 📝 Generate snippet if requested
      if opts.include_content and history then
        result.snippet, result.highlighted_snippet = self:_generate_snippet(history, matches, query)
      end
      
      table.insert(project_results, result)
    end
    
    ::continue::
  end
  
  return project_results, nil
end

---📊 Check if history metadata matches filters
---@param history_info table History metadata
---@param query avante.storage.SearchQuery
---@return boolean matches
function QueryEngine:_matches_metadata_filters(history_info, query)
  -- 📅 Date range filter
  if query.date_range then
    local history_date = history_info.updated_at or history_info.created_at
    if history_date then
      if query.date_range.from and history_date < query.date_range.from then
        return false
      end
      if query.date_range.to and history_date > query.date_range.to then
        return false
      end
    end
  end
  
  -- 📊 Message count filter
  if query.message_count_range then
    local message_count = history_info.message_count or 0
    if query.message_count_range.min and message_count < query.message_count_range.min then
      return false
    end
    if query.message_count_range.max and message_count > query.message_count_range.max then
      return false
    end
  end
  
  -- 📦 Content size filter
  if query.content_size_range then
    local size_estimate = history_info.size_estimate or 0
    if query.content_size_range.min and size_estimate < query.content_size_range.min then
      return false
    end
    if query.content_size_range.max and size_estimate > query.content_size_range.max then
      return false
    end
  end
  
  return true
end

---🔍 Search within history content
---@param history avante.storage.UnifiedChatHistory
---@param query avante.storage.SearchQuery
---@return table[] matches Array of message matches
function QueryEngine:_search_history_content(history, query)
  local matches = {}
  
  for i, message in ipairs(history.messages) do
    local message_matches = {}
    
    -- 👤 Role filter
    if query.role and message.role ~= query.role then
      goto continue
    end
    
    -- 🔍 Text search
    if query.text then
      local content_text = self:_extract_text_content(message)
      if self:_text_matches(content_text, query.text) then
        table.insert(message_matches, {
          type = "content",
          text = content_text,
          match_positions = self:_find_match_positions(content_text, query.text),
        })
      end
    end
    
    -- 🛠️ Tool-related filters
    local tool_matches = self:_search_tool_content(message, query)
    for _, tool_match in ipairs(tool_matches) do
      table.insert(message_matches, tool_match)
    end
    
    -- 🏭 Provider/model filters
    if query.provider and message.provider_info and message.provider_info.provider then
      if not string.match(string.lower(message.provider_info.provider), string.lower(query.provider)) then
        goto continue
      end
    end
    
    if query.model and message.provider_info and message.provider_info.model then
      if not string.match(string.lower(message.provider_info.model), string.lower(query.model)) then
        goto continue
      end
    end
    
    -- 📝 Add message to matches if it has any matches
    if #message_matches > 0 then
      table.insert(matches, {
        message_index = i,
        message_uuid = message.uuid,
        message_role = message.role,
        message_timestamp = message.timestamp,
        matches = message_matches,
      })
    end
    
    ::continue::
  end
  
  return matches
end

---🔍 Search tool-related content in message
---@param message avante.storage.UnifiedHistoryMessage
---@param query avante.storage.SearchQuery
---@return table[] tool_matches
function QueryEngine:_search_tool_content(message, query)
  local tool_matches = {}
  
  -- 🛠️ Check for tool use in message content
  local has_tool_use = false
  local has_tool_error = false
  local tool_names_found = {}
  
  if type(message.content) == "table" then
    for _, content_item in ipairs(message.content) do
      if type(content_item) == "table" then
        if content_item.type == "tool_use" then
          has_tool_use = true
          table.insert(tool_names_found, content_item.name)
          
          -- 📝 Check tool name filter
          if query.tool_names then
            for _, tool_name in ipairs(query.tool_names) do
              if string.match(string.lower(content_item.name), string.lower(tool_name)) then
                table.insert(tool_matches, {
                  type = "tool_use",
                  tool_name = content_item.name,
                  tool_id = content_item.id,
                })
              end
            end
          end
        elseif content_item.type == "tool_result" then
          if content_item.is_error then
            has_tool_error = true
          end
          
          -- 🔍 Search in tool result content
          if query.text and content_item.content then
            if self:_text_matches(content_item.content, query.text) then
              table.insert(tool_matches, {
                type = "tool_result",
                tool_id = content_item.tool_use_id,
                content = content_item.content,
                is_error = content_item.is_error,
              })
            end
          end
        end
      end
    end
  end
  
  -- ✅ Apply tool-related filters
  if query.has_tools ~= nil and query.has_tools ~= has_tool_use then
    return {}
  end
  
  if query.has_errors ~= nil and query.has_errors ~= has_tool_error then
    return {}
  end
  
  return tool_matches
end

---🔍 Check if text matches search query
---@param text string
---@param search_text string
---@return boolean matches
function QueryEngine:_text_matches(text, search_text)
  if not text or not search_text then
    return false
  end
  
  local search_lower = self.config.case_sensitive and search_text or string.lower(search_text)
  local text_lower = self.config.case_sensitive and text or string.lower(text)
  
  if self.config.fuzzy_search then
    -- 🔍 Simple fuzzy matching - check if all characters in search_text appear in order
    local search_pos = 1
    for i = 1, #text_lower do
      if search_pos <= #search_lower and string.sub(text_lower, i, i) == string.sub(search_lower, search_pos, search_pos) then
        search_pos = search_pos + 1
      end
    end
    return search_pos > #search_lower
  else
    -- 📝 Exact substring matching
    return string.find(text_lower, search_lower, 1, true) ~= nil
  end
end

---📍 Find match positions in text for highlighting
---@param text string
---@param search_text string
---@return table[] positions Array of {start, end} positions
function QueryEngine:_find_match_positions(text, search_text)
  local positions = {}
  
  if not text or not search_text then
    return positions
  end
  
  local search_lower = self.config.case_sensitive and search_text or string.lower(search_text)
  local text_lower = self.config.case_sensitive and text or string.lower(text)
  
  local start_pos = 1
  while true do
    local match_start, match_end = string.find(text_lower, search_lower, start_pos, true)
    if not match_start then
      break
    end
    
    table.insert(positions, { start = match_start, ["end"] = match_end })
    start_pos = match_end + 1
  end
  
  return positions
end

---📝 Extract text content from message for searching
---@param message avante.storage.UnifiedHistoryMessage
---@return string text_content
function QueryEngine:_extract_text_content(message)
  if type(message.content) == "string" then
    return message.content
  elseif type(message.content) == "table" then
    local text_parts = {}
    for _, content_item in ipairs(message.content) do
      if type(content_item) == "string" then
        table.insert(text_parts, content_item)
      elseif type(content_item) == "table" and content_item.type == "text" then
        table.insert(text_parts, content_item.text or content_item.content or "")
      end
    end
    return table.concat(text_parts, " ")
  end
  return ""
end

---📊 Calculate relevance score for search result
---@param history_info table History metadata
---@param history? avante.storage.UnifiedChatHistory Full history (if loaded)
---@param matches table[] Content matches
---@param query avante.storage.SearchQuery
---@return number score Relevance score (0-1)
function QueryEngine:_calculate_relevance_score(history_info, history, matches, query)
  local score = 0
  
  -- 📝 Base score from number of matches
  if #matches > 0 then
    score = score + math.min(#matches * 0.1, 0.5) -- Up to 0.5 for matches
  end
  
  -- 📅 Recency boost
  local age_days = 0
  if history_info.updated_at then
    local history_time = Utils.parse_timestamp(history_info.updated_at)
    if history_time then
      age_days = (os.time() - history_time) / (24 * 60 * 60)
    end
  end
  
  -- 📈 More recent conversations get higher scores
  local recency_score = math.max(0, 1 - (age_days / 365)) * 0.3 -- Up to 0.3 for recency
  score = score + recency_score
  
  -- 📊 Size-based scoring
  local message_count = history_info.message_count or 0
  local size_score = math.min(message_count / 100, 0.2) -- Up to 0.2 for conversation size
  score = score + size_score
  
  return math.min(score, 1.0)
end

---📝 Generate text snippet from search results
---@param history avante.storage.UnifiedChatHistory
---@param matches table[]
---@param query avante.storage.SearchQuery
---@return string snippet
---@return string? highlighted_snippet
function QueryEngine:_generate_snippet(history, matches, query)
  if #matches == 0 then
    -- 📝 Return first few messages as snippet
    local snippet_parts = {}
    for i = 1, math.min(3, #history.messages) do
      local text = self:_extract_text_content(history.messages[i])
      if #text > 0 then
        table.insert(snippet_parts, string.sub(text, 1, 100))
      end
    end
    local snippet = table.concat(snippet_parts, " ... ")
    return snippet, snippet
  end
  
  -- 📝 Generate snippet from matches
  local best_match = matches[1]
  if #best_match.matches > 0 then
    local match_info = best_match.matches[1]
    if match_info.text then
      local snippet = string.sub(match_info.text, 1, 200)
      local highlighted = snippet
      
      -- 🎨 Add highlighting if enabled
      if self.config.highlight_matches and query.text then
        for _, pos in ipairs(match_info.match_positions or {}) do
          local before = string.sub(snippet, 1, pos.start - 1)
          local match_text = string.sub(snippet, pos.start, pos["end"])
          local after = string.sub(snippet, pos["end"] + 1)
          highlighted = before .. "**" .. match_text .. "**" .. after
        end
      end
      
      return snippet, highlighted
    end
  end
  
  return "", ""
end

-- 🔧 Helper methods for additional functionality

function QueryEngine:_get_search_cache_key(query, opts)
  return vim.json.encode({ query = query, opts = opts })
end

function QueryEngine:_get_all_projects()
  -- 📁 This would need to be implemented based on storage engine capabilities
  -- For now, return empty list with error
  return {}, "Project discovery not implemented"
end

function QueryEngine:_sort_search_results(results, sort_by, sort_order)
  local compare_fn
  if sort_by == "date" then
    compare_fn = function(a, b)
      return (a.metadata.updated_at or "") > (b.metadata.updated_at or "")
    end
  elseif sort_by == "size" then
    compare_fn = function(a, b)
      return (a.metadata.message_count or 0) > (b.metadata.message_count or 0)
    end
  else -- "relevance"
    compare_fn = function(a, b)
      return a.score > b.score
    end
  end
  
  if sort_order == "asc" then
    local original_fn = compare_fn
    compare_fn = function(a, b)
      return not original_fn(a, b)
    end
  end
  
  table.sort(results, compare_fn)
end

function QueryEngine:_paginate_results(results, limit, offset)
  local paginated = {}
  for i = offset + 1, math.min(offset + limit, #results) do
    table.insert(paginated, results[i])
  end
  return paginated
end

---🔍 Advanced query builders for common use cases

---🛠️ Find conversations with specific tool usage
---@param tool_name string
---@param project_name? string
---@return avante.storage.SearchResult[]
function QueryEngine:find_tool_usage(tool_name, project_name)
  local query = {
    tool_names = { tool_name },
    project_name = project_name,
  }
  local results, _ = self:search(query)
  return results or {}
end

---❌ Find conversations with tool errors
---@param project_name? string
---@return avante.storage.SearchResult[]
function QueryEngine:find_tool_errors(project_name)
  local query = {
    has_errors = true,
    project_name = project_name,
  }
  local results, _ = self:search(query)
  return results or {}
end

---📅 Find recent conversations
---@param days_back number
---@param project_name? string
---@return avante.storage.SearchResult[]
function QueryEngine:find_recent_conversations(days_back, project_name)
  local from_date = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - (days_back * 24 * 60 * 60))
  local query = {
    date_range = { from = from_date },
    project_name = project_name,
  }
  local results, _ = self:search(query, { sort_by = "date" })
  return results or {}
end

---🔍 Full text search
---@param text string
---@param project_name? string
---@return avante.storage.SearchResult[]
function QueryEngine:full_text_search(text, project_name)
  local query = {
    text = text,
    project_name = project_name,
  }
  local results, _ = self:search(query)
  return results or {}
end

return M