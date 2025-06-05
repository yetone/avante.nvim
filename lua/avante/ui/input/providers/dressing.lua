local api = vim.api
local fn = vim.fn

local M = {}

---@param input avante.ui.Input
function M.show(input)
  local ok, dressing_input = pcall(require, "dressing.input")
  if not ok then
    vim.notify("dressing.nvim not found, falling back to native input", vim.log.levels.WARN)
    require("avante.ui.input.providers.native").show(input)
    return
  end

  -- Store state for concealing functionality
  local state = { winid = nil, input_winid = nil, input_bufnr = nil }

  local function setup_concealing()
    if not input.conceal then return end

    vim.defer_fn(function()
      -- Find the dressing input window
      for _, winid in ipairs(api.nvim_list_wins()) do
        local bufnr = api.nvim_win_get_buf(winid)
        if vim.bo[bufnr].filetype == "DressingInput" then
          state.input_winid = winid
          state.input_bufnr = bufnr
          vim.wo[winid].conceallevel = 2
          vim.wo[winid].concealcursor = "nvi"

          -- Set up concealing syntax
          local prompt_length = api.nvim_strwidth(fn.prompt_getprompt(state.input_bufnr))
          api.nvim_buf_call(
            state.input_bufnr,
            function()
              vim.cmd(string.format(
                [[
              syn region SecretValue start=/^/ms=s+%s end=/$/ contains=SecretChar
              syn match SecretChar /./ contained conceal cchar=*
            ]],
                prompt_length
              ))
            end
          )
          break
        end
      end
    end, 50)
  end

  -- Enhanced functionality for concealed input
  vim.ui.input({
    prompt = input.title,
    default = input.default,
    completion = input.completion,
  }, function(result)
    input.on_submit(result)
    -- Close the dressing input window after submission if we have concealing
    if input.conceal then pcall(dressing_input.close) end
  end)

  -- Set up concealing if needed
  setup_concealing()
end

return M
