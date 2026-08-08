local Config = require("avante.config")
local Providers = require("avante.providers")

local function setup_config()
  Config.setup({
    provider = "ollama",
    providers = {
      ollama = {
        __inherited = "openai",
        endpoint = "http://127.0.0.1:11434",
        model = "qwen-test",
        is_env_set = function() return true end,
      },
    },
    behaviour = {
      support_paste_from_clipboard = false,
      enable_token_counting = false,
    },
    mode = "agentic",
  })
end

local function tool_use_messages(history)
  return vim.tbl_filter(function(m)
    local c = m.message and m.message.content
    return type(c) == "table" and c[1] and c[1].type == "tool_use"
  end, history)
end

describe("ollama provider", function()
  before_each(function()
    setup_config()
  end)

  it("adds completed ReAct tool_use messages to history before firing the stop event", function()
    local history = {}
    local stop_events = {}
    local opts = {
      on_messages_add = function(msgs)
        msgs = vim.islist(msgs) and msgs or { msgs }
        for _, m in ipairs(msgs) do
          history[#history + 1] = m
        end
      end,
      on_stop = function(stop) stop_events[#stop_events + 1] = stop end,
      on_chunk = function() end,
    }
    local ctx = { content = "", content_uuid = "uuid-1", turn_id = "turn-1" }

    Providers.openai:add_text_message(
      ctx,
      '<tool_use>{"name":"str_replace","input":{"path":"src/main.ts","old_str":"a","new_str":"b"}}</tool_use>',
      "generating",
      opts
    )

    assert.are.same(1, #stop_events)
    assert.is_false(stop_events[1].streaming_tool_use)
    local tool_uses = tool_use_messages(history)
    assert.are.same(1, #tool_uses)
    assert.are.same("generated", tool_uses[1].state)
    assert.are.same("str_replace", tool_uses[1].message.content[1].name)
  end)

  it("marks incomplete ReAct tool calls as generating and streams the stop event", function()
    local history = {}
    local stop_events = {}
    local opts = {
      on_messages_add = function(msgs)
        msgs = vim.islist(msgs) and msgs or { msgs }
        for _, m in ipairs(msgs) do
          history[#history + 1] = m
        end
      end,
      on_stop = function(stop) stop_events[#stop_events + 1] = stop end,
      on_chunk = function() end,
    }
    local ctx = { content = "", content_uuid = "uuid-2", turn_id = "turn-2" }

    Providers.openai:add_text_message(ctx, '<tool_use>{"name":"str_replace","input":{"path":"src/ma', "generating", opts)

    assert.are.same(1, #stop_events)
    assert.is_true(stop_events[1].streaming_tool_use)
    local tool_uses = tool_use_messages(history)
    assert.are.same(1, #tool_uses)
    assert.are.same("generating", tool_uses[1].state)
  end)

  it("emits a single stop event for multiple ReAct tool calls in one message", function()
    local history = {}
    local stop_events = {}
    local opts = {
      on_messages_add = function(msgs)
        msgs = vim.islist(msgs) and msgs or { msgs }
        for _, m in ipairs(msgs) do
          history[#history + 1] = m
        end
      end,
      on_stop = function(stop) stop_events[#stop_events + 1] = stop end,
      on_chunk = function() end,
    }
    local ctx = { content = "", content_uuid = "uuid-3", turn_id = "turn-3" }

    Providers.openai:add_text_message(ctx, [[
<tool_use>{"name":"glob","input":{"path":"src"}}</tool_use>
<tool_use>{"name":"grep","input":{"pattern":"#","path":"src"}}</tool_use>
<tool_use>{"name":"attempt_completion","input":{"result":"done"}}</tool_use>
]], "generating", opts)

    assert.are.same(1, #stop_events)
    assert.is_false(stop_events[1].streaming_tool_use)
    assert.are.same(3, #tool_use_messages(history))
  end)

  it("dedupes streamed native tool_calls and completes them when the stream is done", function()
    local history = {}
    local stop_events = {}
    local opts = {
      on_messages_add = function(msgs)
        msgs = vim.islist(msgs) and msgs or { msgs }
        for _, m in ipairs(msgs) do
          history[#history + 1] = m
        end
      end,
      on_stop = function(stop) stop_events[#stop_events + 1] = stop end,
      on_chunk = function() end,
    }
    local ctx = { turn_id = "turn-4" }
    local partial_chunk = vim.json.encode({
      message = {
        role = "assistant",
        content = "",
        tool_calls = { { ["function"] = { name = "str_replace", arguments = { path = "src" } } } },
      },
      done = false,
    })
    local final_chunk = vim.json.encode({
      message = {
        role = "assistant",
        content = "",
        tool_calls = {
          { ["function"] = { name = "str_replace", arguments = { path = "src/main.ts", old_str = "a", new_str = "b" } } },
        },
      },
      done = false,
    })
    local done_chunk = vim.json.encode({ message = { role = "assistant", content = "" }, done = true })

    Providers.ollama:parse_stream_data(ctx, partial_chunk, opts)
    Providers.ollama:parse_stream_data(ctx, final_chunk, opts)
    Providers.ollama:parse_stream_data(ctx, done_chunk, opts)

    assert.are.same(1, #stop_events)
    assert.are.same("tool_use", stop_events[1].reason)
    local tool_uses = tool_use_messages(history)
    local first_uuid = tool_uses[1].uuid
    local same_uuid_count = 0
    for _, m in ipairs(tool_uses) do
      if m.uuid == first_uuid then same_uuid_count = same_uuid_count + 1 end
    end
    assert.are.same(#tool_uses, same_uuid_count)
    assert.are.same("generated", tool_uses[#tool_uses].state)
    local completed = tool_uses[#tool_uses].message.content[1].input
    assert.are.same("src/main.ts", completed.path)
    assert.are.same("b", completed.new_str)
  end)
end)
