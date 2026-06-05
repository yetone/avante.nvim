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

    -- If on_delete_item or on_write_item callback is provided, prompt for action
    local has_actions = type(selector.on_delete_item) == "function"
      or type(selector.on_write_item) == "function"
    if has_actions then
      local prompt_parts = { "(o)pen" }
      if type(selector.on_delete_item) == "function" then table.insert(prompt_parts, "(d)elete") end
      if type(selector.on_write_item) == "function" then table.insert(prompt_parts, "(w)rite") end
      table.insert(prompt_parts, "(c)ancel")
      local prompt = "Action for '" .. item.title .. "': " .. table.concat(prompt_parts, ", ") .. "?"
      vim.ui.input({ prompt = prompt, default = "" }, function(input)
        if not input then -- User cancelled input
          selector.on_select(nil) -- Treat as cancellation of selection
          return
        end
        local choice = input:lower()
        if choice == "d" or choice == "delete" then
          if type(selector.on_delete_item) == "function" then
            selector.on_delete_item(item.id)
            -- Re-open the selector to refresh the list
            selector.on_open()
          end
        elseif choice == "w" or choice == "write" then
          if type(selector.on_write_item) == "function" then
            selector.on_write_item(item.id)
          end
        elseif choice == "" or choice == "o" or choice == "open" then
          selector.on_select({ item.id })
        elseif choice == "c" or choice == "cancel" then
          if type(selector.on_open) == "function" then
            selector.on_open()
          else
            selector.on_select(nil) -- Fallback if on_open is not defined
          end
        else -- any other input, treat as cancel
          selector.on_select(nil)
        end
      end)
    else
      -- Default behavior: directly select the item
      selector.on_select({ item.id })
    end
  end)
end

return M
