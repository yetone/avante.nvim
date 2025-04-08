local api = vim.api

---@class CommandsSource : cmp.Source
local CommandsSource = {}
CommandsSource.__index = CommandsSource

function CommandsSource:new()
  local instance = setmetatable({}, CommandsSource)

  return instance
end

function CommandsSource:is_available() return vim.bo.filetype == "AvanteInput" end

function CommandsSource.get_position_encoding_kind() return "utf-8" end

function CommandsSource:get_trigger_characters() return { "/" } end

function CommandsSource:get_keyword_pattern() return [[\%(@\|#\|/\)\k*]] end

function CommandsSource:complete(_, callback)
  local Utils = require("avante.utils")
  local kind = require("cmp").lsp.CompletionItemKind.Variable
  local commands = Utils.get_commands()

  local items = {}

  for _, command in ipairs(commands) do
    table.insert(items, {
      label = "/" .. command.name,
      kind = kind,
      detail = command.details,
      data = {
        name = command.name,
      },
    })
  end

  callback({
    items = items,
    isIncomplete = false,
  })
end

function CommandsSource:execute(item, callback)
  local Utils = require("avante.utils")
  local commands = Utils.get_commands()
  local command = vim.iter(commands):find(function(command) return command.name == item.data.name end)

  if not command then return end

  local sidebar = require("avante").get()
  command.callback(sidebar, nil, function()
    local bufnr = sidebar.input_container.bufnr ---@type integer
    local content = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        local lines = vim.split(content:gsub(item.label, ""), "\n") ---@type string[]
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      end
    end, 100)
    callback()
  end)
end

return CommandsSource
