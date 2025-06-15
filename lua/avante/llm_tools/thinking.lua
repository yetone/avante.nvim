local Line = require("avante.ui.line")
local Base = require("avante.llm_tools.base")
local Highlights = require("avante.highlights")
local Utils = require("avante.utils")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "thinking"

M.description =
  "A tool for thinking through problems, brainstorming ideas, or planning without executing any actions. Use this tool when you need to work through complex problems, develop strategies, or outline approaches before taking action."

M.support_streaming = true

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "content",
      description = "Content to think about. This should be a description of what to think about or a problem to solve.",
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
---@field content string

---@type avante.LLMToolOnRender<ThinkingInput>
function M.on_render(opts, _, state)
  local lines = {}
  local text = state == "generating" and "Thinking" or "Thoughts"
  table.insert(lines, Line:new({ { Utils.icon("🤔 ") .. text, Highlights.AVANTE_THINKING } }))
  table.insert(lines, Line:new({ { "" } }))
  local content = opts.content or ""
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
