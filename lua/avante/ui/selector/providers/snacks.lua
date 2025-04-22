local Utils = require("avante.utils")
local M = {}

---@param selector avante.ui.Selector
function M.show(selector)
  ---@diagnostic disable-next-line: undefined-field
  if not _G.Snacks then
    Utils.error("Snacks is not set up. Please install and set up Snacks to use it as a file selector.")
    return
  end
  local finder_items = {}
  for i, item in ipairs(selector.items) do
    if not vim.list_contains(selector.selected_item_ids, item.id) then
      table.insert(finder_items, {
        formatted = item.title,
        text = item.title,
        item = item,
        idx = i,
        preview = selector.get_preview_content and (function()
          local content, filetype = selector.get_preview_content(item.id)
          return {
            text = content,
            ft = filetype,
          }
        end)() or nil,
      })
    end
  end
  local completed = false
  ---@diagnostic disable-next-line: undefined-global
  Snacks.picker.pick({
    source = "select",
    items = finder_items,
    ---@diagnostic disable-next-line: undefined-global
    format = Snacks.picker.format.ui_select(nil, #finder_items),
    title = selector.title,
    preview = selector.get_preview_content and "preview" or nil,
    layout = {
      preset = "default",
      preview = selector.get_preview_content ~= nil,
    },
    confirm = function(picker)
      if completed then return end
      completed = true
      picker:close()
      local items = picker:selected({ fallback = true })
      local selected_item_ids = vim.tbl_map(function(item) return item.item.id end, items)
      selector.on_select(selected_item_ids)
    end,
    on_close = function()
      if completed then return end
      completed = true
      vim.schedule(function() selector.on_select(nil) end)
    end,
  })
end

return M
