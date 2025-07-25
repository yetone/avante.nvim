local ReActParser = require("avante.libs.ReAct_parser")

local text = "Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt</path><content>foo</content></write></tool_use>"
local result, state = ReActParser.parse(text)

print("Result count:", #result)
for i, item in ipairs(result) do
  print(string.format("Item %d: type=%s", i, item.type))
  if item.type == "tool_use" then
    print(string.format("  - tool_name=%s, partial=%s", item.tool_name, tostring(item.partial)))
  end
end

print("\nState:")
print("completion_phase:", state.completion_phase)
print("tool_buffer count:", #state.tool_buffer)
print("last_processed_position:", state.last_processed_position)
print("total_content_length:", state.total_content_length)