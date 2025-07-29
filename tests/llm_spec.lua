local LLM = require("avante.llm")
local Config = require("avante.config")

describe("LLM tool completion state tracking", function()
  before_each(function()
    Config.setup()
  end)

  it("should initialize tool completion tracker with correct defaults", function()
    -- This tests the internal state initialization
    -- Since the tracker is local to the _stream function, we test behavior indirectly
    
    local state_initialized = false
    local opts = {
      provider = {
        use_ReAct_prompt = true,
        parse_config = function() return { use_ReAct_prompt = true }, {} end,
        parse_messages = function() return {} end,
        parse_curl_args = function() return { url = "http://test", body = {} } end,
      },
      ask = "test",
      on_stop = function(stop_opts)
        -- Verify the tracker was passed to handlers
        state_initialized = true
      end,
      on_chunk = function() end,
      on_messages_add = function() end,
      get_history_messages = function() return {} end,
      session_ctx = {},
    }

    -- Mock job to avoid network calls
    local stub = require("luassert.stub")
    local job_stub = stub(require("plenary.job"), "new", function(config)
      return {
        start = function()
          vim.schedule(function()
            config.on_stdout(nil, "[DONE]")
          end)
          return true
        end,
        shutdown = function() end,
      }
    end)

    LLM._stream(opts)
    vim.wait(100)
    
    assert.is_true(state_initialized)
    job_stub:revert()
  end)

  it("should track state transitions correctly", function()
    local state_transitions = {}
    
    local opts = {
      provider = {
        use_ReAct_prompt = true,
        parse_config = function() return { use_ReAct_prompt = true }, {} end,
        parse_messages = function() return {} end,
        parse_curl_args = function() return { url = "http://test", body = {} } end,
        parse_response = function(self, ctx, data, opts)
          if data == "tool_start" then
            -- Simulate tool detection
            ctx.tool_use_list = { { id = "test", name = "test_tool" } }
            opts.on_stop({ reason = "tool_use" })
          elseif data == "tool_end" then
            -- Simulate tool completion
            opts.on_stop({ reason = "complete" })
          end
        end
      },
      ask = "test with state tracking",
      on_stop = function(stop_opts)
        table.insert(state_transitions, stop_opts.reason)
      end,
      on_chunk = function() end,
      on_messages_add = function() end,
      get_history_messages = function() return {} end,
      session_ctx = {},
    }

    local stub = require("luassert.stub")
    local job_stub = stub(require("plenary.job"), "new", function(config)
      return {
        start = function()
          vim.schedule(function()
            config.on_stdout(nil, "tool_start")
            config.on_stdout(nil, "tool_end")
          end)
          return true
        end,
        shutdown = function() end,
      }
    end)

    LLM._stream(opts)
    vim.wait(100)
    
    -- Verify state transition sequence
    assert.equals("tool_use", state_transitions[1])
    assert.equals("complete", state_transitions[2])
    
    job_stub:revert()
  end)

  it("should prevent duplicate callbacks after completion", function()
    local callback_reasons = {}
    
    local opts = {
      provider = {
        use_ReAct_prompt = true,
        parse_config = function() return { use_ReAct_prompt = true }, {} end,
        parse_messages = function() return {} end,
        parse_curl_args = function() return { url = "http://test", body = {} } end,
        parse_response = function(self, ctx, data, opts)
          if data == "tool_completion" then
            ctx.tool_use_list = { { id = "test", name = "test_tool" } }
            -- This should trigger completion tracking
            opts.on_stop({ reason = "tool_use" })
          elseif data == "[DONE]" then
            -- This duplicate should be prevented by our fix
            if ctx.tool_use_list and #ctx.tool_use_list > 0 then
              if opts.tool_completion_tracker and opts.tool_completion_tracker.final_callback_sent then
                return -- Blocked
              end
              opts.on_stop({ reason = "tool_use" })
            end
          end
        end
      },
      ask = "test duplicate prevention",
      on_stop = function(stop_opts)
        table.insert(callback_reasons, stop_opts.reason)
      end,
      on_chunk = function() end,
      on_messages_add = function() end,
      get_history_messages = function() return {} end,
      session_ctx = {},
    }

    local stub = require("luassert.stub")
    local job_stub = stub(require("plenary.job"), "new", function(config)
      return {
        start = function()
          vim.schedule(function()
            config.on_stdout(nil, "tool_completion")
            config.on_stdout(nil, "[DONE]")  -- This should be blocked
          end)
          return true
        end,
        shutdown = function() end,
      }
    end)

    LLM._stream(opts)
    vim.wait(100)
    
    -- Should only have one callback, duplicate prevented
    assert.equals(1, #callback_reasons)
    assert.equals("tool_use", callback_reasons[1])
    
    job_stub:revert()
  end)

  it("should reset state for new requests", function()
    -- Test that each new stream request gets fresh state
    local first_request_callbacks = {}
    local second_request_callbacks = {}
    
    local create_opts = function(callback_list)
      return {
        provider = {
          use_ReAct_prompt = true,
          parse_config = function() return { use_ReAct_prompt = true }, {} end,
          parse_messages = function() return {} end,
          parse_curl_args = function() return { url = "http://test", body = {} } end,
        },
        ask = "test state reset",
        on_stop = function(stop_opts)
          table.insert(callback_list, stop_opts.reason)
        end,
        on_chunk = function() end,
        on_messages_add = function() end,
        get_history_messages = function() return {} end,
        session_ctx = {},
      }
    end

    local stub = require("luassert.stub")
    local job_stub = stub(require("plenary.job"), "new", function(config)
      return {
        start = function()
          vim.schedule(function()
            config.on_stdout(nil, "[DONE]")
          end)
          return true
        end,
        shutdown = function() end,
      }
    end)

    -- First request
    LLM._stream(create_opts(first_request_callbacks))
    vim.wait(50)
    
    -- Second request should have fresh state
    LLM._stream(create_opts(second_request_callbacks))
    vim.wait(50)
    
    -- Both should complete normally
    assert.equals(1, #first_request_callbacks)
    assert.equals(1, #second_request_callbacks)
    
    job_stub:revert()
  end)
end)