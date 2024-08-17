local api = vim.api

---@class avante.View
---@field buf integer
---@field win integer
---@field RESULT_BUF_NAME string
local View = {}

local RESULT_BUF_NAME = "AVANTE_RESULT"

function View:new()
  return setmetatable({ buf = nil, win = nil }, { __index = View })
end

---setup view buffer
---@param split_command string A split command to position the side bar to
---@param size integer a given % to resize the chat window
---@return avante.View
function View:setup(split_command, size)
  -- create a scratch unlisted buffer
  self.buf = api.nvim_create_buf(false, true)

  -- set filetype
  api.nvim_set_option_value("filetype", "Avante", { buf = self.buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = self.buf })
  api.nvim_set_option_value("modifiable", false, { buf = self.buf })
  api.nvim_set_option_value("swapfile", false, { buf = self.buf })

  -- create a split
  vim.cmd(split_command)

  --get current window and attach the buffer to it
  self.win = api.nvim_get_current_win()
  api.nvim_win_set_buf(self.win, self.buf)

  vim.cmd("vertical resize " .. size)

  -- win stuff
  api.nvim_set_option_value("spell", false, { win = self.win })
  api.nvim_set_option_value("signcolumn", "no", { win = self.win })
  api.nvim_set_option_value("foldcolumn", "0", { win = self.win })
  api.nvim_set_option_value("number", false, { win = self.win })
  api.nvim_set_option_value("relativenumber", false, { win = self.win })
  api.nvim_set_option_value("list", false, { win = self.win })
  api.nvim_set_option_value("wrap", true, { win = self.win })
  api.nvim_set_option_value("winhl", "", { win = self.win })

  -- buffer stuff
  api.nvim_buf_set_name(self.buf, RESULT_BUF_NAME)

  return self
end

function View:close()
  if self.win then
    api.nvim_win_close(self.win, true)
    self.win = nil
    self.buf = nil
  end
end

function View:is_open()
  return self.win and self.buf and api.nvim_buf_is_valid(self.buf) and api.nvim_win_is_valid(self.win)
end

return View
