local Utils = require("avante.utils")

---@class avante.ui.InputOption
---@field provider avante.InputProvider
---@field title string
---@field default string | nil
---@field completion string | nil
---@field provider_opts table | nil
---@field on_submit fun(result: string | nil)
---@field conceal boolean | nil -- Whether to conceal input (for passwords)

---@class avante.ui.Input
---@field provider avante.InputProvider
---@field title string
---@field default string | nil
---@field completion string | nil
---@field provider_opts table | nil
---@field on_submit fun(result: string | nil)
---@field conceal boolean | nil
local Input = {}
Input.__index = Input

---@param opts avante.ui.InputOption
function Input:new(opts)
  local o = {}
  setmetatable(o, Input)
  o.provider = opts.provider
  o.title = opts.title
  o.default = opts.default or ""
  o.completion = opts.completion
  o.provider_opts = opts.provider_opts or {}
  o.on_submit = opts.on_submit
  o.conceal = opts.conceal or false
  return o
end

function Input:open()
  if type(self.provider) == "function" then
    self.provider(self)
    return
  end

  local ok, provider = pcall(require, "avante.ui.input.providers." .. self.provider)
  if not ok then Utils.error("Unknown input provider: " .. self.provider) end
  provider.show(self)
end

return Input
