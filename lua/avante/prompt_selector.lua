local Utils = require("avante.utils")
local Config = require("avante.config")
local Selector = require("avante.ui.selector")
local Path = require("plenary.path")

---@class avante.PromptSelector
local M = {}

---Get prompts directory for current project
---@param project_root string
---@return Path
local function get_prompts_dir(project_root)
  -- Generate SHA hash of the project root directory
  local hash = vim.fn.sha256(project_root)
  
  -- Use ~/.avante/prompts/HASH/
  local home = vim.fn.expand("~")
  return Path:new(home)
    :joinpath(".avante")
    :joinpath("prompts")
    :joinpath(hash)
end

---Load a single prompt file
---@param prompts_dir Path
---@param filepath string Relative path from prompts_dir
---@return table|nil
local function load_prompt_file(prompts_dir, filepath)
  local prompt_file = prompts_dir:joinpath(filepath)
  if not prompt_file:exists() then
    return nil
  end
  
  local content = prompt_file:read()
  if not content then
    return nil
  end
  
  local ok, prompt_data = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end
  
  return prompt_data
end

---Get all prompts from all projects
---@return table[]
local function get_all_prompts()
  local home = vim.fn.expand("~")
  local base_prompts_dir = Path:new(home):joinpath(".avante"):joinpath("prompts")
  
  if not base_prompts_dir:exists() then
    return {}
  end
  
  local all_prompts = {}
  local Scan = require("plenary.scandir")
  
  -- Get all project directories (each is a SHA hash)
  local project_dirs = Scan.scan_dir(tostring(base_prompts_dir), {
    hidden = false,
    add_dirs = true,
    only_dirs = true,
    depth = 1
  })
  
  -- Load prompts from each project
  for _, project_dir_path in ipairs(project_dirs) do
    local project_dir = Path:new(project_dir_path)
    
    -- Scan all JSON files in this project directory
    local files = Scan.scan_dir(tostring(project_dir), {
      hidden = false,
      add_dirs = false,
      respect_gitignore = false,
      search_pattern = "%.json$"
    })
    
    for _, filepath in ipairs(files) do
      if not filepath:match("index%.json$") then
        local file = Path:new(filepath)
        local content = file:read()
        if content then
          local ok, prompt_data = pcall(vim.json.decode, content)
          if ok and prompt_data then
            table.insert(all_prompts, prompt_data)
          end
        end
      end
    end
  end
  
  -- Sort by usage_count DESC, then unix_time DESC (smart ranking)
  table.sort(all_prompts, function(a, b)
    local a_usage = a.usage_count or 0
    local b_usage = b.usage_count or 0
    
    if a_usage ~= b_usage then
      return a_usage > b_usage  -- Higher usage first
    end
    
    return (a.unix_time or 0) > (b.unix_time or 0)  -- Then by recency
  end)
  
  return all_prompts
end

---Format prompt for selector display
---@param prompt_data table
---@return table
local function to_selector_item(prompt_data)
  local preview = prompt_data.prompt:sub(1, 50):gsub("\n", " ")
  if #prompt_data.prompt > 50 then
    preview = preview .. "..."
  end
  
  -- Extract project name from project_root (last component of path)
  local project_name = "unknown"
  if prompt_data.metadata and prompt_data.metadata.project_root then
    project_name = prompt_data.metadata.project_root:match("([^/]+)$") or "unknown"
  end
  
  -- Add usage count if greater than 0
  local usage_count = prompt_data.usage_count or 0
  local usage_display = usage_count > 0 and string.format(" (used %dx)", usage_count) or ""
  
  local display = string.format(
    "%s | [%s] | %s%s",
    prompt_data.timestamp,
    project_name,
    preview,
    usage_display
  )
  
  return {
    id = prompt_data.id,
    title = display,
    prompt_data = prompt_data,
  }
end

---Generate preview content for a prompt
---@param prompt_data table
---@return string, string
local function generate_preview(prompt_data)
  local lines = {}
  
  table.insert(lines, "# Prompt Details")
  table.insert(lines, "")
  table.insert(lines, "**Timestamp:** " .. prompt_data.timestamp)
  table.insert(lines, "**ID:** " .. prompt_data.id)
  
  -- Show usage statistics
  local usage_count = prompt_data.usage_count or 0
  table.insert(lines, "**Usage Count:** " .. usage_count)
  
  if prompt_data.last_used then
    local last_used_date = os.date("%Y-%m-%d %H:%M:%S", prompt_data.last_used)
    table.insert(lines, "**Last Used:** " .. last_used_date)
  end
  
  table.insert(lines, "")
  
  if prompt_data.metadata then
    table.insert(lines, "## Metadata")
    table.insert(lines, "")
    
    local meta = prompt_data.metadata
    if meta.project_root then
      table.insert(lines, "- **Project:** `" .. meta.project_root .. "`")
    end
    if meta.working_directory then
      table.insert(lines, "- **Working Dir:** `" .. meta.working_directory .. "`")
    end
    if meta.is_first_prompt ~= nil then
      table.insert(lines, "- **First Prompt:** " .. tostring(meta.is_first_prompt))
    end
    if meta.current_file and meta.current_file ~= "" then
      table.insert(lines, "- **Current File:** `" .. meta.current_file .. "`")
    end
    if meta.filetype then
      table.insert(lines, "- **File Type:** `" .. meta.filetype .. "`")
    end
    if meta.provider then
      table.insert(lines, "- **Provider:** " .. meta.provider)
    end
    if meta.model then
      table.insert(lines, "- **Model:** " .. meta.model)
    end
    if meta.current_mode_id then
      table.insert(lines, "- **Mode:** " .. meta.current_mode_id)
    end
    
    if meta.selected_files and #meta.selected_files > 0 then
      table.insert(lines, "")
      table.insert(lines, "### Selected Files")
      table.insert(lines, "")
      for _, file in ipairs(meta.selected_files) do
        table.insert(lines, "- `" .. file .. "`")
      end
    end
  end
  
  table.insert(lines, "")
  table.insert(lines, "## Prompt")
  table.insert(lines, "")
  table.insert(lines, "```")
  table.insert(lines, prompt_data.prompt)
  table.insert(lines, "```")
  
  return table.concat(lines, "\n"), "markdown"
end

---Open prompt selector
---@param opts? table
function M.open(opts)
  opts = opts or {}
  
  -- Get current project root
  local ok, project_root = pcall(Utils.root.get)
  if not ok or not project_root then
    Utils.warn("Could not determine project root")
    return
  end
  
  -- Load all prompts
  local prompts = get_all_prompts(project_root)
  
  if #prompts == 0 then
    Utils.warn("No prompts found for this project")
    return
  end
  
  -- Convert to selector items
  local selector_items = {}
  for _, prompt_data in ipairs(prompts) do
    table.insert(selector_items, to_selector_item(prompt_data))
  end
  
  -- Prepare provider-specific options for full-text search
  local provider_opts = {}
  
  -- For Telescope: use custom entry_maker to search full prompt content
  if Config.selector.provider == "telescope" then
    local has_telescope, _ = pcall(require, "telescope")
    if has_telescope then
      local finders = require("telescope.finders")
      local conf = require("telescope.config").values
      
      provider_opts.finder = finders.new_table({
        results = selector_items,
        entry_maker = function(entry)
          return {
            value = entry.id,
            display = entry.title,
            ordinal = entry.prompt_data.prompt,  -- Search full prompt, not just title
          }
        end,
      })
      provider_opts.sorter = conf.generic_sorter({})  -- Use generic sorter for text matching
    end
  end
  
  -- Create selector
  local current_selector = Selector:new({
    provider = Config.selector.provider,
    title = "Avante Prompts - Select to Reuse",
    items = selector_items,
    provider_opts = provider_opts,
    on_select = function(item_ids)
      if not item_ids or #item_ids == 0 then return end
      
      -- Find the selected prompt
      local selected_id = item_ids[1]
      local selected_prompt = nil
      for _, item in ipairs(selector_items) do
        if item.id == selected_id then
          selected_prompt = item.prompt_data
          break
        end
      end
      
      if not selected_prompt then
        Utils.warn("Could not find selected prompt")
        return
      end
      
      -- Increment usage count before inserting
      local PromptLogger = require("avante.utils.promptLogger")
      PromptLogger.increment_usage_count(selected_prompt.id)
      
      -- Insert the prompt into the sidebar input
      local Sidebar = require("avante.sidebar")
      local sidebar = Sidebar.get()
      if sidebar and sidebar.containers.input then
        local prompt_lines = vim.split(selected_prompt.prompt, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(sidebar.containers.input.bufnr, 0, -1, false, prompt_lines)
        
        -- Focus the input window
        if sidebar.containers.input.winid and vim.api.nvim_win_is_valid(sidebar.containers.input.winid) then
          vim.api.nvim_set_current_win(sidebar.containers.input.winid)
          -- Move cursor to end
          local line_count = vim.api.nvim_buf_line_count(sidebar.containers.input.bufnr)
          local last_line = vim.api.nvim_buf_get_lines(sidebar.containers.input.bufnr, -2, -1, false)[1]
          vim.api.nvim_win_set_cursor(sidebar.containers.input.winid, { line_count, #last_line })
        end
        
        Utils.info("Prompt loaded into input")
      else
        Utils.warn("Sidebar input not available")
      end
    end,
    get_preview_content = function(item_id)
      -- Find the prompt data
      for _, item in ipairs(selector_items) do
        if item.id == item_id then
          return generate_preview(item.prompt_data)
        end
      end
      return "Prompt not found", "markdown"
    end,
  })
  
  current_selector:open()
end

return M