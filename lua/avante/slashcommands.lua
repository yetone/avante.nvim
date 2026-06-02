---@mod avante-slashcommands avante slash commands
---@brief [[
---Built-in slash commands available in the Avante input buffer.
---
--- Slash commands are triggered by typing `/` at the beginning of a chat
--- message. Commands with callbacks are handled locally by Avante; other
--- commands may rewrite the prompt before it is submitted.
---
--- - `/help`: show available commands
--- - `/init`: initialize AGENTS.md based on the current project
--- - `/clear`: clear chat history
--- - `/new`: start a new chat
--- - `/compact`: compact history messages
--- - `/simplify`: aggressively simplify chat history, keeping only critical engineering context
--- - `/model`: select model
--- - `/lines <start>-<end> <question>`: ask about specific lines
--- - `/commit`: generate a commit message
--- - `/send <instance-name> <message>`: send a message to another Avante instance (hidden when ipc_service is enabled)
---@brief ]]

---@class avante.SlashCommands
---@field get_builtin_commands fun(): AvanteSlashCommand[]

local M = {}

---@type AvanteSlashCommand[]
local builtin_commands = {
  {
    description = "Show help message",
    details = "Show help message",
    name = "help",
  },
  {
    description = "Init AGENTS.md based on the current project",
    details = "Init AGENTS.md based on the current project",
    name = "init",
  },
  {
    description = "Clear chat history",
    details = "Clear chat history",
    name = "clear",
  },
  {
    description = "New chat",
    details = "New chat",
    name = "new",
  },
  {
    description = "Compact history messages to save tokens",
    details = "Compact history messages to save tokens",
    name = "compact",
  },
  {
    description = "Maximally simplify history, keeping only critical engineering context",
    details = "Maximally simplify history, keeping only critical engineering context",
    name = "simplify",
  },
  {
    description = "Select model",
    details = "Select model",
    name = "model",
  },
  {
    shorthelp = "Ask a question about specific lines",
    description = "/lines <start>-<end> <question>",
    details = "Ask a question about specific lines\n/lines <start>-<end> <question>",
    name = "lines",
  },
  {
    description = "Commit the changes",
    details = "Commit the changes",
    name = "commit",
  },
  {
    shorthelp = "Send a message to another Avante instance",
    description = "/send <instance-name> <intent>",
    details = "Ask the current chat's model to draft and send a message to another active Avante instance\n/send <instance-name> <what to communicate>",
    name = "send",
  },
}

---@param commands AvanteSlashCommand[]
---@return string
local function get_help_text(commands)
  local help_text = ""
  for _, command in ipairs(commands) do
    help_text = help_text .. "- " .. command.name .. ": " .. (command.shorthelp or command.description) .. "\n"
  end
  return help_text
end

---@type {[AvanteSlashCommandBuiltInName]: AvanteSlashCommandCallback}
local callbacks = {
  help = function(sidebar, args, cb)
    sidebar:update_content(get_help_text(builtin_commands), { focus = false, scroll = false })
    if cb then cb(args) end
  end,
  clear = function(sidebar, args, cb) sidebar:clear_history(args, cb) end,
  new = function(sidebar, args, cb) sidebar:new_chat(args, cb) end,
  compact = function(sidebar, args, cb) sidebar:compact_history_messages(args, cb) end,
  simplify = function(sidebar, args, cb) sidebar:simplify_history_messages(args, cb) end,
  init = function(sidebar, args, cb) sidebar:init_current_project(args, cb) end,
  lines = function(_, args, cb)
    if cb then cb(args) end
  end,
  commit = function(_, _, cb)
    local question = "Please commit the changes"
    if cb then cb(question) end
  end,
  model = function(_, _, cb)
    local Config = require("avante.config")
    local api = require("avante.api")
    if Config.acp_providers[Config.provider] then
      api.select_acp_model()
    else
      api.select_model()
    end
    if cb then cb("") end
  end,
  -- /send is a convenience wrapper around the send_message LLM tool for
  -- in-process (same-nvim) instance messaging.  When the IPC service is
  -- enabled the LLM tool handles cross-process delivery directly, so /send
  -- is redundant and would only confuse the model with stale in-process-only
  -- semantics.  We keep the callback in case someone invokes it at runtime
  -- but filter the command out of the visible list below.
  send = function(sidebar, args, cb) sidebar:send_message_to_instance(args, cb) end,
}

---@return AvanteSlashCommand[]
function M.get_builtin_commands()
  local Config = require("avante.config")
  local ipc_enabled = Config.ipc_service and Config.ipc_service.enabled
  return vim
    .iter(builtin_commands)
    :filter(function(command)
      -- Hide /send when the IPC service is enabled — cross-process messaging
      -- is handled transparently by the send_message LLM tool instead.
      if command.name == "send" and ipc_enabled then return false end
      return true
    end)
    :map(
      ---@param command AvanteSlashCommand
      function(command)
        local command_ = vim.deepcopy(command)
        command_.callback = callbacks[command.name]
        return command_
      end
    )
    :totable()
end

return M
