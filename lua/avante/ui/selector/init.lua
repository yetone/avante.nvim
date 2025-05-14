local Utils = require("avante.utils")

---@class avante.ui.SelectorItem
---@field id string
---@field title string

---@class avante.ui.SelectorOption
---@field provider avante.SelectorProvider
---@field title string
---@field items avante.ui.SelectorItem[]
---@field default_item_id string | nil
---@field selected_item_ids string[] | nil
---@field provider_opts table | nil
---@field on_select fun(item_ids: string[] | nil)
---@field get_preview_content fun(item_id: string): (string, string) | nil

---@class avante.ui.Selector
---@field provider avante.SelectorProvider
---@field title string
---@field items avante.ui.SelectorItem[]
---@field default_item_id string | nil
---@field provider_opts table | nil
---@field on_select fun(item_ids: string[] | nil)
---@field selected_item_ids string[] | nil
---@field get_preview_content fun(item_id: string): (string, string) | nil
local Selector = {}
Selector.__index = Selector

---@param opts avante.ui.SelectorOption
function Selector:new(opts)
  local o = {}
  setmetatable(o, Selector)
  o.provider = opts.provider
  o.title = opts.title
  o.items = vim
    .iter(opts.items)
    :map(function(item)
      local new_item = vim.deepcopy(item)
      new_item.title = new_item.title:gsub("\n", " ")
      return new_item
    end)
    :totable()
  o.default_item_id = opts.default_item_id
  o.provider_opts = opts.provider_opts or {}
  o.on_select = opts.on_select
  o.selected_item_ids = opts.selected_item_ids or {}
  o.get_preview_content = opts.get_preview_content
  return o
end

function Selector:open()
  if type(self.provider) == "function" then
    self.provider(self)
    return
  end

  local ok, provider = pcall(require, "avante.ui.selector.providers." .. self.provider)
  if not ok then Utils.error("Unknown file selector provider: " .. self.provider) end
  provider.show(self)
end

return Selector
