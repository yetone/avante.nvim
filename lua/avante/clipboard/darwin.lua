local Utils = require("avante.utils")

---@class AvanteClipboard
local M = {}

---@alias DarwinClipboardCommand "pngpaste" | "osascript"
M.clip_cmd = nil

---@return DarwinClipboardCommand
M.get_clip_cmd = function()
  if M.clip_cmd then
    return M.clip_cmd
  end
  if vim.fn.executable("pngpaste") == 1 then
    M.clip_cmd = "pngpaste"
  elseif vim.fn.executable("osascript") == 1 then
    M.clip_cmd = "osascript"
  end
  return M.clip_cmd
end

M.has_content = function()
  local cmd = M.get_clip_cmd()
  ---@type vim.SystemCompleted
  local output

  if cmd == "pngpaste" then
    output = Utils.shell_run("pngpaste -")
    return output.code == 0
  elseif cmd == "osascript" then
    output = Utils.shell_run("osascript -e 'clipboard info'")
    return output.code == 0 and output.stdout ~= nil and output.stdout:find("class PNGf") ~= nil
  end

  Utils.warn("Failed to validate clipboard content", { title = "Avante" })
  return false
end

M.save_content = function(filepath)
  local cmd = M.get_clip_cmd()
  ---@type vim.SystemCompleted
  local output

  if cmd == "pngpaste" then
    output = Utils.shell_run(('pngpaste - > "%s"'):format(filepath))
    return output.code == 0
  elseif cmd == "osascript" then
    output = Utils.shell_run(
      string.format(
        [[osascript -e 'set theFile to (open for access POSIX file "%s" with write permission)' ]]
          .. [[-e 'try' -e 'write (the clipboard as «class PNGf») to theFile' -e 'end try' ]]
          .. [[-e 'close access theFile' -e 'do shell script "cat %s > %s"']],
        filepath,
        filepath,
        filepath
      )
    )
    return output.code == 0
  end
  return false
end

M.get_base64_content = function()
  local cmd = M.get_clip_cmd()
  ---@type vim.SystemCompleted
  local output

  if cmd == "pngpaste" then
    output = Utils.shell_run("pngpaste - | base64 | tr -d '\n'")
    if output.code == 0 then
      return output.stdout
    end
  elseif cmd == "osascript" then
    output = Utils.shell_run(
      [[osascript -e 'set theFile to (open for access POSIX file "/tmp/image.png" with write permission)' -e 'try' -e 'write (the clipboard as «class PNGf») to theFile' -e 'end try' -e 'close access theFile'; ]]
        .. [[cat /tmp/image.png | base64 | tr -d '\n']]
    )
    if output.code == 0 then
      return output.stdout
    end
  end
  error("Failed to get clipboard content")
end

return M
