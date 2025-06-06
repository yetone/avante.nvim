local M = {}

---@param input avante.ui.Input
function M.show(input)
  local ok, snacks_input = pcall(require, "snacks.input")
  if not ok then
    vim.notify("snacks.nvim not found, falling back to native input", vim.log.levels.WARN)
    require("avante.ui.input.providers.native").show(input)
    return
  end

  local opts = vim.tbl_deep_extend("force", {
    prompt = input.title,
    default = input.default,
  }, input.provider_opts)

  -- Add concealing support if needed
  if input.conceal then opts.password = true end

  snacks_input(opts, input.on_submit)
end

return M
