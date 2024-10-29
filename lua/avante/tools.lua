local Utils = require("avante.utils")

---@class AvanteToolUse
local tool_lib = nil

local M = {}

M.setup = function()
  -- vim.defer_fn(function()
  --   local ok, core = pcall(require, "avante_tool_use")
  --   if not ok then
  --     error("Failed to load avante_tool_use")
  --     return
  --   end
  --
  --   if tool_lib == nil then tool_lib = core end
  -- end, 1000)
end

return M
