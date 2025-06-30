local Line = require("avante.ui.line")
local Base = require("avante.llm_tools.base")
local Highlights = require("avante.highlights")
local Utils = require("avante.utils")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "think"

M.description =
  [[Use the tool to think about something. It will not obtain new information or make any changes to the repository, but just log the thought. Use it when complex reasoning or brainstorming is needed. For example, if you explore the repo and discover the source of a bug, call this tool to brainstorm several unique ways of fixing the bug, and assess which change(s) are likely to be simplest and most effective. Alternatively, if you receive some test results, call this tool to brainstorm ways to fix the failing tests.

RULES:
- Remember to frequently use the `think` tool to resolve tasks, especially before each tool call.
]]

M.support_streaming = true

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "thought",
      description = "Your thoughts.",
      type = "string",
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "Whether the task was completed successfully",
    type = "string",
  },
  {
    name = "thoughts",
    description = "The thoughts that guided the solution",
    type = "string",
  },
}

---@class ThinkingInput
---@field thought string

---@type avante.LLMToolOnRender<ThinkingInput>
function M.on_render(opts, _, state)
  local lines = {}
  local text = state == "generating" and "Thinking" or "Thoughts"
  table.insert(lines, Line:new({ { Utils.icon("🤔 ") .. text, Highlights.AVANTE_THINKING } }))
  table.insert(lines, Line:new({ { "" } }))
  local content = opts.thought or ""
  local text_lines = vim.split(content, "\n")
  for _, text_line in ipairs(text_lines) do
    table.insert(lines, Line:new({ { "> " .. text_line } }))
  end
  return lines
end

---@type AvanteLLMToolFunc<ThinkingInput>
function M.func(opts, on_log, on_complete, session_ctx)
  if not on_complete then return false, "on_complete not provided" end
  on_complete(true, nil)
end

return M
