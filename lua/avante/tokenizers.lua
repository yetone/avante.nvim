---@class AvanteTokenizer
---@field from_pretrained fun(model: string): nil
---@field encode fun(string): integer[]
local tokenizers = nil

local M = {}

---@param model "gpt-4o" | string
M.setup = function(model)
  local ok, core = pcall(require, "avante_tokenizers")
  if not ok then
    return
  end

  ---@cast core AvanteTokenizer
  core.from_pretrained(model)
  tokenizers = core
end

M.available = function()
  return tokenizers ~= nil
end

---@param prompt string
M.encode = function(prompt)
  if not tokenizers then
    return nil
  end
  if not prompt or prompt == "" then
    return nil
  end
  if type(prompt) ~= "string" then
    error("Prompt is not type string", 2)
  end

  return tokenizers.encode(prompt)
end

---@param prompt string
M.count = function(prompt)
  if not tokenizers then
    return math.ceil(#prompt * 0.5)
  end

  local tokens = M.encode(prompt)
  if not tokens then
    return 0
  end
  return #tokens
end

return M
