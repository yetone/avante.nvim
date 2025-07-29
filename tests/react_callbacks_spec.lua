local stub = require("luassert.stub")
local spy = require("luassert.spy")
local LLM = require("avante.llm")
local Config = require("avante.config")
local Utils = require("avante.utils")

describe("ReAct callbacks", function()
  local mock_provider
  local callback_spy
  local tool_completion_tracker

  before_each(function()
    Config.setup()
    
    -- Create spy for on_stop callbacks
    callback_spy = spy.new(function() end)
    
    -- Mock provider with ReAct support
    mock_provider = {
      use_ReAct_prompt = true,
      parse_config = function() 
        return { use_ReAct_prompt = true }, {}
      end,
      parse_messages = function() return {} end,
      parse_curl_args = function() 
        return { url = "http://test", body = {} }
      end,
      parse_response = function(self, ctx, data, opts)
        -- Simulate tool completion followed by [DONE]
        if data == "tool_data" then
          ctx.tool_use_list = { { id = "test_tool", name = "test" } }
          opts.on_stop({ reason = "tool_use" })
        elseif data == "[DONE]" then
          -- This simulates the duplicate callback that should be prevented
          if ctx.tool_use_list and #ctx.tool_use_list > 0 then
            local provider_conf = { use_ReAct_prompt = true }
            if opts.tool_completion_tracker then
              if opts.tool_completion_tracker.final_callback_sent then
                Utils.debug("Test: Blocked duplicate tool_use callback after completion")
                return
              end
              if opts.tool_completion_tracker.completion_in_progress then
                Utils.debug("Test: Blocked duplicate tool_use callback during processing")
                return
              end
            end
            opts.on_stop({ reason = "tool_use" })
          else
            opts.on_stop({ reason = "complete" })
          end
        end
      end
    }
    
    -- Stub external dependencies
    stub(Utils, "get_project_root", function() return "/tmp/test" end)
  end)

  after_each(function()
    Utils.get_project_root:revert()
  end)

  it("should prevent duplicate tool_use callbacks in ReAct mode", function()
    local callback_count = 0
    local on_stop_calls = {}
    
    local opts = {
      provider = mock_provider,
      ask = "test question",
      on_stop = function(stop_opts)
        callback_count = callback_count + 1
        table.insert(on_stop_calls, stop_opts.reason)
        callback_spy(stop_opts)
      end,
      on_chunk = function() end,
      on_messages_add = function() end,
      get_history_messages = function() return {} end,
      session_ctx = {},
    }

    -- Mock job creation to avoid actual network calls
    local job_stub = stub(require("plenary.job"), "new", function(config)
      local mock_job = {
        start = function()
          -- Simulate streaming response
          vim.schedule(function()
            config.on_stdout(nil, "tool_data")  -- First callback: tool_use
            config.on_stdout(nil, "[DONE]")     -- Second callback: should be blocked
          end)
          return true
        end,
        shutdown = function() end,
      }
      return mock_job
    end)

    -- Execute the test
    LLM._stream(opts)
    
    -- Wait for async operations
    vim.wait(100)
    
    -- Verify only one tool_use callback was made
    assert.equals(1, callback_count)
    assert.equals("tool_use", on_stop_calls[1])
    
    job_stub:revert()
  end)

  it("should allow normal callbacks when not in ReAct mode", function()
    -- Override provider to disable ReAct
    mock_provider.use_ReAct_prompt = false
    mock_provider.parse_config = function() 
      return { use_ReAct_prompt = false }, {}
    end

    local callback_count = 0
    local on_stop_calls = {}
    
    local opts = {
      provider = mock_provider,
      ask = "test question",
      on_stop = function(stop_opts)
        callback_count = callback_count + 1
        table.insert(on_stop_calls, stop_opts.reason)
      end,
      on_chunk = function() end,
      on_messages_add = function() end,
      get_history_messages = function() return {} end,
      session_ctx = {},
    }

    -- Mock job that simulates normal completion
    local job_stub = stub(require("plenary.job"), "new", function(config)
      local mock_job = {
        start = function()
          vim.schedule(function()
            config.on_stdout(nil, "tool_data")  -- Tool callback
            config.on_stdout(nil, "[DONE]")     -- Completion callback - should work
          end)
          return true
        end,
        shutdown = function() end,
      }
      return mock_job
    end)

    LLM._stream(opts)
    vim.wait(100)
    
    -- Should allow both callbacks in non-ReAct mode
    assert.equals(2, callback_count)
    assert.equals("tool_use", on_stop_calls[1])
    assert.equals("tool_use", on_stop_calls[2])  -- Not blocked in non-ReAct mode
    
    job_stub:revert()
  end)

  it("should handle multiple sequential tools correctly", function()
    local callback_count = 0
    local on_stop_calls = {}
    
    local opts = {
      provider = mock_provider,
      ask = "test question with multiple tools",
      on_stop = function(stop_opts)
        callback_count = callback_count + 1
        table.insert(on_stop_calls, stop_opts.reason)
      end,
      on_chunk = function() end,
      on_messages_add = function() end,
      get_history_messages = function() return {} end,
      session_ctx = {},
    }

    local job_stub = stub(require("plenary.job"), "new", function(config)
      local mock_job = {
        start = function()
          vim.schedule(function()
            -- First tool
            config.on_stdout(nil, "tool_data")
            -- Second tool (simulated by another call)
            config.on_stdout(nil, "tool_data")
            -- Final completion
            config.on_stdout(nil, "[DONE]")
          end)
          return true
        end,
        shutdown = function() end,
      }
      return mock_job
    end)

    LLM._stream(opts)
    vim.wait(100)
    
    -- Should handle sequential tools without duplicates
    assert.is_true(callback_count >= 1)
    assert.equals("tool_use", on_stop_calls[1])
    
    job_stub:revert()
  end)
end)