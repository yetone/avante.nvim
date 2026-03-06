local M = {}

---@param selector avante.ui.Selector
function M.show(selector)
  local items = {}
  for _, item in ipairs(selector.items) do
    if not vim.list_contains(selector.selected_item_ids, item.id) then table.insert(items, item) end
  end
  vim.ui.select(items, {
    prompt = selector.title,
    format_item = function(item)
      local title = item.title
      if item.id == selector.default_item_id then title = "● " .. title end
      return title
    end,
  }, function(item)
    if not item then
      selector.on_select(nil)
      return
    end

    -- If on_delete_item callback is provided, prompt for action
    if type(selector.on_delete_item) == "function" then
      vim.ui.select({ "Open", "Delete", "Cancel" }, {
        prompt = "Action for '" .. item.title .. "':",
      }, function(choice)
        if choice == "Open" then
          selector.on_select({ item.id })
          return
        elseif choice == "Delete" then
          selector.on_delete_item(item.id)
        end

        if type(selector.on_open) == "function" then
          selector.on_open() -- Re-open the selector to refresh the list
        else
          selector.on_select(nil) -- Fallback if on_open is not defined
        end
      end)
    else
      -- Default behavior: directly select the item
      selector.on_select({ item.id })
    end
  end)
end

return M
