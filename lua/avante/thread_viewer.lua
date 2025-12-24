local History = require("avante.history")
local Utils = require("avante.utils")
local Path = require("avante.path")

---@class avante.ThreadViewer
local M = {}

---@param history avante.ChatHistory
---@return string
local function format_thread_entry(history)
  local messages = History.get_history_messages(history)
  local timestamp = #messages > 0 and messages[#messages].timestamp or history.timestamp
  local working_dir = history.working_directory or "unknown"
  
  -- Extract just the directory name for display
  local dir_name = working_dir:match("([^/]+)$") or working_dir
  
  -- Format: [dir_name] title - timestamp (msg_count messages)
  return string.format("[%s] %s - %s (%d)", 
    dir_name, 
    history.title, 
    timestamp, 
    #messages
  )
end

---@param bufnr integer
---@param cb fun(filename: string)
function M.open_with_telescope(bufnr, cb)
  local has_telescope, _ = pcall(require, "telescope")
  if not has_telescope then
    Utils.warn("Telescope is not installed. Please install telescope.nvim to use :AvanteThreads")
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local histories = Path.history.list(bufnr)

  if #histories == 0 then
    Utils.warn("No thread history found.")
    return
  end

  -- Create entries for telescope
  local entries = {}
  for _, history in ipairs(histories) do
    table.insert(entries, {
      value = history.filename,
      display = format_thread_entry(history),
      ordinal = format_thread_entry(history),
      history = history,
    })
  end

  pickers
    .new({}, {
      prompt_title = "Avante Threads",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return entry
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = "Thread Preview",
        define_preview = function(self, entry)
          local history = entry.history
          local Sidebar = require("avante.sidebar")
          local content = Sidebar.render_history_content(history)
          
          -- Add directory context at the top
          local preview_lines = {}
          if history.working_directory then
            table.insert(preview_lines, "**Working Directory:** " .. history.working_directory)
            table.insert(preview_lines, "")
          end
          if history.acp_session_id then
            table.insert(preview_lines, "**ACP Session ID:** " .. history.acp_session_id)
            table.insert(preview_lines, "")
          end
          table.insert(preview_lines, "---")
          table.insert(preview_lines, "")
          
          -- Append the actual content
          for line in content:gmatch("[^\r\n]+") do
            table.insert(preview_lines, line)
          end
          
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
          vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          -- Wrap close in pcall to handle potential autocmd errors
          pcall(actions.close, prompt_bufnr)
          if selection and cb then
            vim.schedule(function()
              cb(selection.value)
            end)
          end
        end)

        -- Add delete mapping with 'd'
        map("n", "d", function()
          local selection = action_state.get_selected_entry()
          if selection then
            Path.history.delete(bufnr, selection.value)
            Utils.info("Deleted thread: " .. selection.display)
            -- Wrap close in pcall to handle potential autocmd errors
            pcall(actions.close, prompt_bufnr)
            -- Reopen the picker to refresh (with slight delay to avoid conflicts)
            vim.schedule(function()
              M.open_with_telescope(bufnr, cb)
            end)
          end
        end)

        return true
      end,
    })
    :find()
end

---@param bufnr integer
---@param cb fun(filename: string)
function M.open(bufnr, cb)
  -- Try to use telescope first, fall back to native selector
  local has_telescope, _ = pcall(require, "telescope")
  
  if has_telescope then
    M.open_with_telescope(bufnr, cb)
  else
    -- Fall back to the native history selector
    require("avante.history_selector").open(bufnr, cb)
  end
end

return M
