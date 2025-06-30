local Base = require("avante.llm_tools.base")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "add_todos"

M.description = "Add TODOs to the current task"

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "todos",
      description = "The TODOs to add",
      type = "array",
      items = {
        name = "items",
        type = "object",
        fields = {
          {
            name = "id",
            description = "The ID of the TODO",
            type = "string",
          },
          {
            name = "content",
            description = "The content of the TODO",
            type = "string",
          },
          {
            name = "status",
            description = "The status of the TODO",
            type = "string",
            choices = { "todo", "doing", "done", "cancelled" },
          },
          {
            name = "priority",
            description = "The priority of the TODO",
            type = "string",
            choices = { "low", "medium", "high" },
          },
        },
      },
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "Whether the TODOs were added successfully",
    type = "boolean",
  },
  {
    name = "error",
    description = "Error message if the TODOs could not be updated",
    type = "string",
    optional = true,
  },
}

M.on_render = function() return {} end

---@type AvanteLLMToolFunc<{ todos: avante.TODO[] }>
function M.func(opts, on_log, on_complete, session_ctx)
  local sidebar = require("avante").get()
  if not sidebar then return false, "Avante sidebar not found" end
  local todos = opts.todos
  if not todos or #todos == 0 then return false, "No todos provided" end
  sidebar:update_todos(todos)
  if on_complete then
    on_complete(true, nil)
    return nil, nil
  end
  return true, nil
end

return M
