-- Extracted from: https://github.com/MunifTanjim/nui.nvim/blob/main/lua/nui/utils/keymap.lua
local buf_storage = require("avante.utils.buf_storage")
local utils = require("avante.utils")

local api = vim.api

local keymap = {
  storage = buf_storage.create("avante.utils.keymap", { _next_handler_id = 1, keys = {}, handlers = {} }),
}

---@param mode string
---@param key string
---@return string key_id
local function get_key_id(mode, key)
  return string.format("%s---%s", mode, vim.api.nvim_replace_termcodes(key, true, true, true))
end

---@param bufnr number
---@param key_id string
---@return integer|nil handler_id
local function get_handler_id(bufnr, key_id)
  return keymap.storage[bufnr].keys[key_id]
end

---@param bufnr number
---@param mode string
---@param key string
---@param handler string|fun(): nil
---@return { rhs: string, callback?: fun(): nil }|nil
local function get_keymap_info(bufnr, mode, key, handler, overwrite)
  local key_id = get_key_id(mode, key)

  -- luacov: disable
  if get_handler_id(bufnr, key_id) and not overwrite then
    return nil
  end
  -- luacov: enable

  local rhs, callback = "", nil

  if type(handler) == "function" then
    callback = handler
  else
    rhs = handler
  end

  return {
    rhs = rhs,
    callback = callback,
  }
end

---@param bufnr number
---@param mode string|string[]
---@param lhs string|string[]
---@param handler string|fun(): nil
---@param opts? vim.keymap.set.Opts
---@return nil
function keymap.set(bufnr, mode, lhs, handler, opts, force)
  if not utils.is_type("boolean", force) then
    force = true
  end

  local keys = lhs
  if type(lhs) ~= "table" then
    keys = { lhs }
  end
  ---@cast keys -string

  opts = opts or {}

  if not utils.is_type("nil", opts.remap) then
    opts.noremap = not opts.remap
    opts.remap = nil
  end

  local modes = {}
  if type(mode) == "string" then
    modes = { mode }
  else
    modes = mode
  end

  for _, key in ipairs(keys) do
    for _, mode_ in ipairs(modes) do
      local keymap_info = get_keymap_info(bufnr, mode_, key, handler, force)
      -- luacov: disable
      if not keymap_info then
        return false
      end
      -- luacov: enable

      local options = vim.deepcopy(opts)
      options.callback = keymap_info.callback

      api.nvim_buf_set_keymap(bufnr, mode_, key, keymap_info.rhs, options)
    end
  end

  return true
end

return keymap
