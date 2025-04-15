local Utils = require("avante.utils")
local M = {}

---@param selector avante.ui.Selector
function M.show(selector)
  local success, fzf_lua = pcall(require, "fzf-lua")
  if not success then
    Utils.error("fzf-lua is not installed. Please install fzf-lua to use it as a file selector.")
    return
  end

  local formated_items = vim.iter(selector.items):map(function(item) return item.title end):totable()
  local title_to_id = {}
  for _, item in ipairs(selector.items) do
    title_to_id[item.title] = item.id
  end

  local function close_action() selector.on_select(nil) end
  fzf_lua.fzf_exec(
    formated_items,
    vim.tbl_deep_extend("force", {
      prompt = selector.title,
      preview = selector.get_preview_content and function(item)
        local id = title_to_id[item[1]]
        local content = selector.get_preview_content(id)
        return content
      end or nil,
      fzf_opts = {},
      git_icons = false,
      actions = {
        ["default"] = function(selected)
          if not selected or #selected == 0 then return close_action() end
          ---@type string[]
          local selections = {}
          for _, entry in ipairs(selected) do
            local id = title_to_id[entry]
            if id then table.insert(selections, id) end
          end

          selector.on_select(selections)
        end,
        ["esc"] = close_action,
        ["ctrl-c"] = close_action,
      },
    }, selector.provider_opts)
  )
end

return M
