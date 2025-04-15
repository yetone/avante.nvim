local M = {}

---@param selector avante.ui.Selector
function M.show(selector)
  local items = {}
  for _, item in ipairs(selector.items) do
    if not vim.list_contains(selector.selected_item_ids, item.id) then table.insert(items, item) end
  end
  vim.ui.select(items, {
    prompt = selector.title,
    format_item = function(item) return item.title end,
  }, function(item)
    if item then
      selector.on_select({ item.id })
    else
      selector.on_select(nil)
    end
  end)
end

return M
