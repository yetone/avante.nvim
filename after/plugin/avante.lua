--- NOTE: We will override vim.paste if img-clip.nvim is available to work with avante.nvim internal logic paste

local Clipboard = require("avante.clipboard")
local Config = require("avante.config")

if Config.support_paste_image() then
  vim.paste = (function(overriden)
    ---@param lines string[]
    ---@param phase -1|1|2|3
    return function(lines, phase)
      local bufnr = vim.api.nvim_get_current_buf()
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
      if filetype ~= "AvanteInput" then
        return overriden(lines, phase)
      end

      ---@type string
      local line = lines[1]

      local ok = Clipboard.paste_image(line)
      if not ok then
        return overriden(lines, phase)
      end

      -- After pasting, insert a new line and set cursor to this line
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
      local last_line = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    end
  end)(vim.paste)
end
