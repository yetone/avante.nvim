local Utils = require("avante.utils")
local Path = require("avante.path")

---@class avante.HistorySelector
local M = {}

---@param history avante.ChatHistory
---@return table?
local function to_selector_item(history)
  local timestamp = #history.entries > 0 and history.entries[#history.entries].timestamp or history.timestamp
  return {
    name = history.title .. " - " .. timestamp .. " (" .. #history.entries .. ")",
    filename = history.filename,
  }
end

---@param bufnr integer
---@param cb fun(filename: string)
function M.open(bufnr, cb)
  local selector_items = {}

  local histories = Path.history.list(bufnr)

  for _, history in ipairs(histories) do
    table.insert(selector_items, to_selector_item(history))
  end

  if #selector_items == 0 then
    Utils.warn("No models available in config")
    return
  end

  local has_telescope, _ = pcall(require, "telescope")
  if has_telescope then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local conf = require("telescope.config").values
    pickers
      .new({}, {
        prompt_title = "Select Avante History",
        finder = finders.new_table(vim.iter(selector_items):map(function(item) return item.name end):totable()),
        sorter = conf.generic_sorter({}),
        previewer = previewers.new_buffer_previewer({
          title = "Preview",
          define_preview = function(self, entry)
            if not entry then return end
            local item = vim.iter(selector_items):find(function(item) return item.name == entry.value end)
            if not item then return end
            local history = Path.history.load(vim.api.nvim_get_current_buf(), item.filename)
            local Sidebar = require("avante.sidebar")
            local content = Sidebar.render_history_content(history)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(content or "", "\n"))
            vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
          end,
        }),
        attach_mappings = function(prompt_bufnr, map)
          map("i", "<CR>", function()
            local selection = action_state.get_selected_entry()
            if selection then
              actions.close(prompt_bufnr)
              local item = vim.iter(selector_items):find(function(item) return item.name == selection.value end)
              if not item then return end
              cb(item.filename)
            end
          end)
          return true
        end,
      })
      :find()
    return
  end

  vim.ui.select(selector_items, {
    prompt = "Select Avante History:",
    format_item = function(item) return item.name end,
  }, function(choice)
    if not choice then return end
    cb(choice.filename)
  end)
end

return M
