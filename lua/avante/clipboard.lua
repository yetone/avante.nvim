---NOTE: this module is inspired by https://github.com/HakonHarnes/img-clip.nvim/tree/main
---@see https://github.com/ekickx/clipboard-image.nvim/blob/main/lua/clipboard-image/paste.lua

local Path = require("plenary.path")
local Utils = require("avante.utils")
local Config = require("avante.config")
---@module "img-clip"
local ImgClip = nil

---@class AvanteClipboard
---@field get_base64_content fun(filepath: string): string | nil
---
---@class avante.Clipboard: AvanteClipboard
local M = {}

---@type Path
local paste_directory = nil

---@return Path
local function get_paste_directory()
  if paste_directory then return paste_directory end
  paste_directory = Path:new(Config.history.storage_path):joinpath("pasted_images")
  return paste_directory
end

M.support_paste_image = Config.support_paste_image

function M.setup()
  get_paste_directory()

  if not paste_directory:exists() then paste_directory:mkdir({ parent = true }) end

  if M.support_paste_image() and ImgClip == nil then ImgClip = require("img-clip") end
end

---@param line? string
function M.paste_image(line)
  line = line or nil
  if not Config.support_paste_image() then return false end

  local opts = {
    dir_path = paste_directory:absolute(),
    prompt_for_file_name = false,
    filetypes = {
      AvanteInput = Config.img_paste,
    },
  }

  if vim.fn.has("wsl") > 0 or vim.fn.has("win32") > 0 then opts.use_absolute_path = true end

  ---@diagnostic disable-next-line: need-check-nil, undefined-field
  return ImgClip.paste_image(opts, line)
end

---@param filepath string
function M.get_base64_content(filepath)
  local os_mapping = Utils.get_os_name()
  ---@type vim.SystemCompleted
  local output
  if os_mapping == "darwin" or os_mapping == "linux" then
    output = Utils.shell_run(("cat %s | base64 | tr -d '\n'"):format(filepath))
  else
    output =
      Utils.shell_run(("([Convert]::ToBase64String([IO.File]::ReadAllBytes('%s')) -replace '`r`n')"):format(filepath))
  end
  if output.code == 0 then
    return output.stdout
  else
    error("Failed to convert image to base64")
  end
end

return M
