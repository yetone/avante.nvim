local Utils = require("avante.utils")

---@class AvanteClipboard
local M = {}

M.clip_cmd = nil

M.get_clip_cmd = function()
  if M.clip_cmd then
    return M.clip_cmd
  end
  if (vim.fn.has("win32") > 0 or vim.fn.has("wsl") > 0) and vim.fn.executable("powershell.exe") then
    M.clip_cmd = "powershell.exe"
  end
  return M.clip_cmd
end

M.has_content = function()
  local cmd = M.get_clip_cmd()
  ---@type vim.SystemCompleted
  local output

  if cmd == "powershell.exe" then
    output =
      Utils.shell_run("Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::GetImage()")
    return output.code == 0 and output.stdout:find("Width") ~= nil
  end

  Utils.warn("Failed to validate clipboard content", { title = "Avante" })
  return false
end

M.save_content = function(filepath)
  local cmd = M.get_clip_cmd()
  ---@type vim.SystemCompleted
  local output

  if cmd == "powershell.exe" then
    output = Utils.shell_run(
      ("Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::GetImage().Save('%s')"):format(
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

  if cmd == "powershell.exe" then
    output = Utils.shell_run(
      [[Add-Type -AssemblyName System.Windows.Forms; $ms = New-Object System.IO.MemoryStream;]]
        .. [[ [System.Windows.Forms.Clipboard]::GetImage().Save($ms, [System.Drawing.Imaging.ImageFormat]::Png);]]
        .. [[ [System.Convert]::ToBase64String($ms.ToArray())]]
    )
    if output.code == 0 then
      return output.stdout:gsub("\r\n", ""):gsub("\n", ""):gsub("\r", "")
    end
  end
  error("Failed to get clipboard content")
end

return M
