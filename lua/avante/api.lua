local Config = require("avante.config")
local Utils = require("avante.utils")
local PromptInput = require("avante.ui.prompt_input")

---@class avante.ApiToggle
---@operator call(): boolean
---@field debug ToggleBind.wrap
---@field hint ToggleBind.wrap

---@class avante.Api
---@field toggle avante.ApiToggle
local M = {}

---@param target_provider avante.SelectorProvider
function M.switch_selector_provider(target_provider)
  require("avante.config").override({
    selector = {
      provider = target_provider,
    },
  })
end

---@param target avante.ProviderName
function M.switch_provider(target) require("avante.providers").refresh(target) end

---@param path string
local function to_windows_path(path)
  local winpath = path:gsub("/", "\\")

  if winpath:match("^%a:") then winpath = winpath:sub(1, 2):upper() .. winpath:sub(3) end

  winpath = winpath:gsub("\\$", "")

  return winpath
end

---@param opts? {source: boolean}
function M.build(opts)
  opts = opts or { source = true }
  local dirname = Utils.trim(string.sub(debug.getinfo(1).source, 2, #"/init.lua" * -1), { suffix = "/" })
  local git_root = vim.fs.find(".git", { path = dirname, upward = true })[1]
  local build_directory = git_root and vim.fn.fnamemodify(git_root, ":h") or (dirname .. "/../../")

  if opts.source and not vim.fn.executable("cargo") then
    error("Building avante.nvim requires cargo to be installed.", 2)
  end

  ---@type string[]
  local cmd
  local os_name = Utils.get_os_name()

  if vim.tbl_contains({ "linux", "darwin" }, os_name) then
    cmd = {
      "sh",
      "-c",
      string.format("make BUILD_FROM_SOURCE=%s -C %s", opts.source == true and "true" or "false", build_directory),
    }
  elseif os_name == "windows" then
    build_directory = to_windows_path(build_directory)
    cmd = {
      "powershell",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      string.format("%s\\Build.ps1", build_directory),
      "-WorkingDirectory",
      build_directory,
      "-BuildFromSource",
      string.format("%s", opts.source == true and "true" or "false"),
    }
  else
    error("Unsupported operating system: " .. os_name, 2)
  end

  ---@type integer
  local pid
  local exit_code = { 0 }

  local ok, job_or_err = pcall(vim.system, cmd, { text = true }, function(obj)
    local stderr = obj.stderr and vim.split(obj.stderr, "\n") or {}
    local stdout = obj.stdout and vim.split(obj.stdout, "\n") or {}
    if vim.tbl_contains(exit_code, obj.code) then
      local output = stdout
      if #output == 0 then
        table.insert(output, "")
        Utils.debug("build output:", output)
      else
        Utils.debug("build error:", stderr)
      end
    end
  end)
  if not ok then Utils.error("Failed to build the command: " .. cmd .. "\n" .. job_or_err, { once = true }) end
  pid = job_or_err.pid
  return pid
end

---@class AskOptions
---@field question? string optional questions
---@field win? table<string, any> windows options similar to |nvim_open_win()|
---@field ask? boolean
---@field floating? boolean whether to open a floating input to enter the question
---@field new_chat? boolean whether to open a new chat
---@field without_selection? boolean whether to open a new chat without selection

---@param opts? AskOptions
function M.ask(opts)
  opts = opts or {}
  if type(opts) == "string" then
    Utils.warn("passing 'ask' as string is deprecated, do {question = '...'} instead", { once = true })
    opts = { question = opts }
  end

  local has_question = opts.question ~= nil and opts.question ~= ""

  if Utils.is_sidebar_buffer(0) and not has_question then
    require("avante").close_sidebar()
    return false
  end

  opts = vim.tbl_extend("force", { selection = Utils.get_visual_selection_and_range() }, opts)

  ---@param input string | nil
  local function ask(input)
    if input == nil or input == "" then input = opts.question end
    local sidebar = require("avante").get()
    if sidebar and sidebar:is_open() and sidebar.code.bufnr ~= vim.api.nvim_get_current_buf() then
      sidebar:close({ goto_code_win = false })
    end
    require("avante").open_sidebar(opts)
    if opts.new_chat then sidebar:new_chat() end
    if opts.without_selection then
      sidebar.code.selection = nil
      sidebar.file_selector:reset()
      if sidebar.selected_files_container then sidebar.selected_files_container:unmount() end
    end
    if input == nil or input == "" then return true end
    vim.api.nvim_exec_autocmds("User", { pattern = "AvanteInputSubmitted", data = { request = input } })
    return true
  end

  if opts.floating == true or (Config.windows.ask.floating == true and not has_question and opts.floating == nil) then
    local prompt_input = PromptInput:new({
      submit_callback = function(input) ask(input) end,
      close_on_submit = true,
      win_opts = {
        border = Config.windows.ask.border,
        title = { { "Avante Ask", "FloatTitle" } },
      },
      start_insert = Config.windows.ask.start_insert,
      default_value = opts.question,
    })
    prompt_input:open()
    return true
  end

  return ask()
end

---@param request? string
---@param line1? integer
---@param line2? integer
function M.edit(request, line1, line2)
  local _, selection = require("avante").get()
  if not selection then return end
  selection:create_editing_input(request, line1, line2)
  if request ~= nil and request ~= "" then
    vim.api.nvim_exec_autocmds("User", { pattern = "AvanteEditSubmitted", data = { request = request } })
  end
end

---@return avante.Suggestion | nil
function M.get_suggestion()
  local _, _, suggestion = require("avante").get()
  return suggestion
end

---@param opts? AskOptions
function M.refresh(opts)
  opts = opts or {}
  local sidebar = require("avante").get()
  if not sidebar then return end
  if not sidebar:is_open() then return end
  local curbuf = vim.api.nvim_get_current_buf()

  local focused = sidebar.result_container.bufnr == curbuf or sidebar.input_container.bufnr == curbuf
  if focused or not sidebar:is_open() then return end
  local listed = vim.api.nvim_get_option_value("buflisted", { buf = curbuf })

  if Utils.is_sidebar_buffer(curbuf) or not listed then return end

  local curwin = vim.api.nvim_get_current_win()

  sidebar:close()
  sidebar.code.winid = curwin
  sidebar.code.bufnr = curbuf
  sidebar:render(opts)
end

---@param opts? AskOptions
function M.focus(opts)
  opts = opts or {}
  local sidebar = require("avante").get()
  if not sidebar then return end

  local curbuf = vim.api.nvim_get_current_buf()
  local curwin = vim.api.nvim_get_current_win()

  if sidebar:is_open() then
    if curbuf == sidebar.input_container.bufnr then
      if sidebar.code.winid and sidebar.code.winid ~= curwin then vim.api.nvim_set_current_win(sidebar.code.winid) end
    elseif curbuf == sidebar.result_container.bufnr then
      if sidebar.code.winid and sidebar.code.winid ~= curwin then vim.api.nvim_set_current_win(sidebar.code.winid) end
    else
      if sidebar.input_container.winid and sidebar.input_container.winid ~= curwin then
        vim.api.nvim_set_current_win(sidebar.input_container.winid)
      end
    end
  else
    if sidebar.code.winid then vim.api.nvim_set_current_win(sidebar.code.winid) end
    ---@cast opts SidebarOpenOptions
    sidebar:open(opts)
    if sidebar.input_container.winid then vim.api.nvim_set_current_win(sidebar.input_container.winid) end
  end
end

function M.select_model() require("avante.model_selector").open() end

function M.select_history()
  local buf = vim.api.nvim_get_current_buf()
  require("avante.history_selector").open(buf, function(filename)
    vim.api.nvim_buf_call(buf, function()
      if not require("avante").is_sidebar_open() then require("avante").open_sidebar({}) end
      local Path = require("avante.path")
      Path.history.save_latest_filename(buf, filename)
      local sidebar = require("avante").get()
      sidebar:update_content_with_history()
      vim.schedule(function() sidebar:focus_input() end)
    end)
  end)
end

function M.add_buffer_files()
  local sidebar = require("avante").get()
  if not sidebar then
    require("avante.api").ask()
    sidebar = require("avante").get()
  end
  if not sidebar:is_open() then sidebar:open({}) end
  sidebar.file_selector:add_buffer_files()
end

function M.stop() require("avante.llm").cancel_inflight_request() end

return setmetatable(M, {
  __index = function(t, k)
    local module = require("avante")
    ---@class AvailableApi: ApiCaller
    ---@field api? boolean
    local has = module[k]
    if type(has) ~= "table" or not has.api then
      Utils.warn(k .. " is not a valid avante's API method", { once = true })
      return
    end
    t[k] = has
    return t[k]
  end,
}) --[[@as avante.Api]]
