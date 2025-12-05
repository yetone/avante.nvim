local ACPClient = require("avante.libs.acp_client")
local stub = require("luassert.stub")

describe("ACPClient", function()
  local schedule_stub
  local setup_transport_stub

  before_each(function()
    schedule_stub = stub(vim, "schedule")
    schedule_stub.invokes(function(fn)
      fn()
    end)
    setup_transport_stub = stub(ACPClient, "_setup_transport")
  end)

  after_each(function()
    schedule_stub:revert()
    setup_transport_stub:revert()
  end)

  describe("_handle_read_text_file", function()
    it("should call error_callback when file read fails", function()
      local sent_error = nil
      local handler_called = false
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function(path, line, limit, success_callback, err_callback)
            handler_called = true
            err_callback("File not found", ACPClient.ERROR_CODES.RESOURCE_NOT_FOUND)
          end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(function(self, id, message, code)
        sent_error = { id = id, message = message, code = code }
      end)

      client:_handle_read_text_file(123, { sessionId = "test-session", path = "/nonexistent/file.txt" })

      assert.is_true(handler_called)
      assert.is_not_nil(sent_error)
      assert.equals(123, sent_error.id)
      assert.equals("File not found", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.RESOURCE_NOT_FOUND, sent_error.code)
    end)

    it("should use default error message when error_callback called with nil", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function(path, line, limit, success_callback, err_callback)
            err_callback(nil, nil)
          end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(function(self, id, message, code)
        sent_error = { id = id, message = message, code = code }
      end)

      client:_handle_read_text_file(456, { sessionId = "test-session", path = "/bad/file.txt" })

      assert.is_not_nil(sent_error)
      assert.equals(456, sent_error.id)
      assert.equals("Failed to read file", sent_error.message)
      assert.is_nil(sent_error.code)
    end)

    it("should call success_callback when file read succeeds", function()
      local sent_result = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function(path, line, limit, success_callback, err_callback)
            success_callback("file contents")
          end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_result = stub().invokes(function(self, id, result)
        sent_result = { id = id, result = result }
      end)

      client:_handle_read_text_file(789, { sessionId = "test-session", path = "/existing/file.txt" })

      assert.is_not_nil(sent_result)
      assert.equals(789, sent_result.id)
      assert.equals("file contents", sent_result.result.content)
    end)

    it("should send error when params are invalid (missing sessionId)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(function(self, id, message, code)
        sent_error = { id = id, message = message, code = code }
      end)

      client:_handle_read_text_file(100, { path = "/file.txt" })

      assert.is_not_nil(sent_error)
      assert.equals(100, sent_error.id)
      assert.equals("Invalid fs/read_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when params are invalid (missing path)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(function(self, id, message, code)
        sent_error = { id = id, message = message, code = code }
      end)

      client:_handle_read_text_file(200, { sessionId = "test-session" })

      assert.is_not_nil(sent_error)
      assert.equals(200, sent_error.id)
      assert.equals("Invalid fs/read_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when handler is not configured", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {},
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(function(self, id, message, code)
        sent_error = { id = id, message = message, code = code }
      end)

      client:_handle_read_text_file(300, { sessionId = "test-session", path = "/file.txt" })

      assert.is_not_nil(sent_error)
      assert.equals(300, sent_error.id)
      assert.equals("fs/read_text_file handler not configured", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.METHOD_NOT_FOUND, sent_error.code)
    end)
  end)

  describe("_handle_write_text_file", function()
    it("should send error when params are invalid (missing sessionId)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_write_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(function(self, id, message, code)
        sent_error = { id = id, message = message, code = code }
      end)

      client:_handle_write_text_file(400, { path = "/file.txt", content = "data" })

      assert.is_not_nil(sent_error)
      assert.equals(400, sent_error.id)
      assert.equals("Invalid fs/write_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when params are invalid (missing path)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_write_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(function(self, id, message, code)
        sent_error = { id = id, message = message, code = code }
      end)

      client:_handle_write_text_file(500, { sessionId = "test-session", content = "data" })

      assert.is_not_nil(sent_error)
      assert.equals(500, sent_error.id)
      assert.equals("Invalid fs/write_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when params are invalid (missing content)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_write_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(function(self, id, message, code)
        sent_error = { id = id, message = message, code = code }
      end)

      client:_handle_write_text_file(600, { sessionId = "test-session", path = "/file.txt" })

      assert.is_not_nil(sent_error)
      assert.equals(600, sent_error.id)
      assert.equals("Invalid fs/write_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when handler is not configured", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {},
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(function(self, id, message, code)
        sent_error = { id = id, message = message, code = code }
      end)

      client:_handle_write_text_file(700, { sessionId = "test-session", path = "/file.txt", content = "data" })

      assert.is_not_nil(sent_error)
      assert.equals(700, sent_error.id)
      assert.equals("fs/write_text_file handler not configured", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.METHOD_NOT_FOUND, sent_error.code)
    end)
  end)
end)
