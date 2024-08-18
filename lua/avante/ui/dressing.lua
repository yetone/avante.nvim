local api, fn = vim.api, vim.fn

---@class avante.Dressing
local H = {}

local C = {
  filetype = "DressingInput",
  conceal_char = "*",
  close_window = function()
    require("dressing.input").close()
  end,
}

---@class avante.DressingState
local state = {
  winid = nil, ---@type integer
  input_winid = nil, ---@type integer
  input_bufnr = nil, ---@type integer
}

---@param options {opts: table<string, any>, on_confirm: fun(value: string): nil} See vim.ui.input for more info
H.initialize_input_buffer = function(options)
  state.winid = api.nvim_get_current_win()
  vim.ui.input(vim.tbl_deep_extend("force", { default = "" }, options.opts), options.on_confirm)
  for _, winid in ipairs(api.nvim_list_wins()) do
    local bufnr = api.nvim_win_get_buf(winid)
    if vim.bo[bufnr].filetype == C.filetype then
      state.input_winid = winid
      state.input_bufnr = bufnr
      vim.wo[winid].conceallevel = 2
      vim.wo[winid].concealcursor = "nvi"
      break
    end
  end

  local prompt_length = api.nvim_strwidth(fn.prompt_getprompt(state.input_bufnr))
  api.nvim_buf_call(state.input_bufnr, function()
    vim.cmd(string.format(
      [[
      syn region SecretValue start=/^/ms=s+%s end=/$/ contains=SecretChar
      syn match SecretChar /./ contained conceal %s
      ]],
      prompt_length,
      "cchar=*"
    ))
  end)
end

---@param switch_buffer? boolean To switch back original buffer, default to tru
H.teardown = function(switch_buffer)
  switch_buffer = switch_buffer or true

  if state.input_winid and api.nvim_win_is_valid(state.input_winid) then
    C.close_window()
    state.input_winid = nil
    if switch_buffer then
      pcall(api.nvim_set_current_win, state.winid)
    end
  end
end

return H
