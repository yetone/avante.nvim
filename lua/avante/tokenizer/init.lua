---reference:
---https://github.com/openai/tiktoken/blob/main/tiktoken/load.py
---https://github.com/openai/tiktoken/blob/main/tiktoken_ext/openai_public.py

local AvantePath = require("avante.path")
local Config = require("avante.config")
local curl = require("plenary.curl")

---@class avante.Tokenizer
local M = {}

ENDOFTEXT = "<|endoftext|>"
FIM_PREFIX = "<|fim_prefix|>"
FIM_MIDDLE = "<|fim_middle|>"
FIM_SUFFIX = "<|fim_suffix|>"
ENDOFPROMPT = "<|endofprompt|>"

M.urls = {
  ["gpt-4o"] = {
    url = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
    hash = "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d",
    special_tokens = {
      [ENDOFTEXT] = 199999,
      [ENDOFPROMPT] = 200018,
    },
  },
  ["gpt-3.5"] = {
    url = "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
    hash = "223921b76ee99bde995b7ff738513eef100fb51d18c93597a113bcffe865b2a7",
    special_tokens = {
      [ENDOFTEXT] = 100257,
      [FIM_PREFIX] = 100258,
      [FIM_MIDDLE] = 100259,
      [FIM_SUFFIX] = 100260,
      [ENDOFPROMPT] = 100276,
    },
  },
}

---@class AvanteTokenizer
---@field encode fun(string): integer[]
---@field count fun(): integer
---
---@class TokenizerState
---@field impl AvanteTokenzer?
---@field type Tokenizer?
M.state = nil

---@param implementation Tokenizer
---@return AvanteTokenizer
M.get = function(implementation)
  if M.state.type ~= implementation then
    M.state = { impl = require("avante.tokenizer." .. implementation), type = implementation }
  end
  return M.state.impl
end

M.setup = function()
  if M.state == nil then
    M.state = { impl = require("avante.tokenizer." .. Config.tokenizer), type = Config.tokenizer }
  end
end

return M
