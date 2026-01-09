local M = {}

---@param selector avante.ui.Selector
function M.show(selector)
  -- First, prompt for custom path input
  vim.ui.input({
    prompt = selector.title .. " (type path or leave empty to select from list): ",
    default = "",
    completion = "file", -- Enable file/directory tab completion
  }, function(custom_path)
    -- If user provided a custom path, use it
    if custom_path and custom_path ~= "" then
      selector.on_select({ custom_path })
      return
    end
    
    -- Otherwise show the selection list
    local items = {}
    for _, item in ipairs(selector.items) do
      if not vim.list_contains(selector.selected_item_ids, item.id) then table.insert(items, item) end
    end
    
    vim.ui.select(items, {
      prompt = selector.title,
      format_item = function(item) return item.title end,
    }, function(item)
    if not item then
      selector.on_select(nil)
      return
    end

    -- If on_delete_item callback is provided, prompt for action
    if type(selector.on_delete_item) == "function" then
      vim.ui.input(
        { prompt = "Action for '" .. item.title .. "': (o)pen, (d)elete, (c)ancel?", default = "" },
        function(input)
          if not input then -- User cancelled input
            selector.on_select(nil) -- Treat as cancellation of selection
            return
          end
          local choice = input:lower()
          if choice == "d" or choice == "delete" then
            selector.on_delete_item(item.id)
            -- The native provider handles the UI flow; we just need to refresh.
            selector.on_open() -- Re-open the selector to refresh the list
          elseif choice == "" or choice == "o" or choice == "open" then
            selector.on_select({ item.id })
          elseif choice == "c" or choice == "cancel" then
            if type(selector.on_open) == "function" then
              selector.on_open()
            else
              selector.on_select(nil) -- Fallback if on_open is not defined
            end
          else -- c or any other input, treat as cancel
            selector.on_select(nil) -- Fallback if on_open is not defined
          end
        end
      )
    else
      -- Default behavior: directly select the item
      selector.on_select({ item.id })
    end
    end)
  end)
end

return M