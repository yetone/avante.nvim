local Utils = require("avante.utils")

---@class AvanteClipboard
local M = {}

M.clip_cmd = nil

M.get_clip_cmd = function()
  if M.clip_cmd then
    return M.clip_cmd
  end
  -- Wayland
  if os.getenv("WAYLAND_DISPLAY") ~= nil and vim.fn.executable("wl-paste") == 1 then
    M.clip_cmd = "wl-paste"
  -- X11
  elseif os.getenv("DISPLAY") ~= nil and vim.fn.executable("xclip") == 1 then
    M.clip_cmd = "xclip"
  end
  return M.clip_cmd
end

M.has_content = function()
  local cmd = M.get_clip_cmd()
  ---@type vim.SystemCompleted
  local output

  -- X11
  if cmd == "xclip" then
    output = Utils.shell_run("xclip -selection clipboard -t TARGETS -o")
    return output.code == 0 and output.stdout:find("image/png") ~= nil
  elseif cmd == "wl-paste" then
    output = Utils.shell_run("wl-paste --list-types")
    return output.code == 0 and output.stdout:find("image/png") ~= nil
  end

  Utils.warn("Failed to validate clipboard content", { title = "Avante" })
  return false
end

M.save_content = function(filepath)
  local cmd = M.get_clip_cmd()
  ---@type vim.SystemCompleted
  local output

  if cmd == "xclip" then
    output = Utils.shell_run(('xclip -selection clipboard -o -t image/png > "%s"'):format(filepath))
    return output.code == 0
  elseif cmd == "wl-paste" then
    output = Utils.shell_run(('wl-paste --type image/png > "%s"'):format(filepath))
    return output.code == 0
  end
  return false
end

M.get_base64_content = function()
  local cmd = M.get_clip_cmd()
  ---@type vim.SystemCompleted
  local output

  if cmd == "xclip" then
    output = Utils.shell_run("xclip -selection clipboard -o -t image/png | base64 | tr -d '\n'")
    if output.code == 0 then
      return output.stdout
    end
  elseif cmd == "osascript" then
    output = Utils.shell_run("wl-paste --type image/png | base64 | tr -d '\n'")
    if output.code == 0 then
      return output.stdout
    end
  end
  error("Failed to get clipboard content")
end

return M
