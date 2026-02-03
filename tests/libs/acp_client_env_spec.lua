local ACPClient = require("avante.libs.acp_client")
local stub = require("luassert.stub")

describe("ACPClient Environment Handling", function()
  local schedule_stub
  local environ_stub
  local spawn_stub
  local uv = vim.uv or vim.loop

  before_each(function()
    schedule_stub = stub(vim, "schedule")
    schedule_stub.invokes(function(fn) fn() end)

    environ_stub = stub(vim.fn, "environ")
    spawn_stub = stub(uv, "spawn")
  end)

  after_each(function()
    schedule_stub:revert()
    environ_stub:revert()
    spawn_stub:revert()
  end)

  it("should inherit all environment variables when no overrides are provided", function()
    -- Mock environment
    environ_stub.returns({
      USER = "testuser",
      HOME = "/home/testuser",
      PATH = "/usr/bin:/bin"
    })

    -- Mock successful spawn
    spawn_stub.returns({}, 1234)

    local config = {
      transport_type = "stdio",
      command = "test-agent",
      args = {},
      env = nil -- No overrides
    }

    local client = ACPClient:new(config)
    client:connect(function() end)

    assert.stub(spawn_stub).was_called(1)
    local call_args = spawn_stub.calls[1].refs
    local options = call_args[2]
    local env_list = options.env

    -- Verify env list contains all inherited variables
    local env_map = {}
    for _, item in ipairs(env_list) do
      local k, v = item:match("([^=]+)=(.*)")
      env_map[k] = v
    end

    assert.equals("testuser", env_map["USER"])
    assert.equals("/home/testuser", env_map["HOME"])
    assert.equals("/usr/bin:/bin", env_map["PATH"])
  end)

  it("should override existing environment variables", function()
    -- Mock environment
    environ_stub.returns({
      USER = "testuser",
      HOME = "/home/testuser",
      PATH = "/usr/bin:/bin"
    })

    -- Mock successful spawn
    spawn_stub.returns({}, 1234)

    local config = {
      transport_type = "stdio",
      command = "test-agent",
      args = {},
      env = {
        HOME = "/home/override"
      }
    }

    local client = ACPClient:new(config)
    client:connect(function() end)

    assert.stub(spawn_stub).was_called(1)
    local call_args = spawn_stub.calls[1].refs
    local options = call_args[2]
    local env_list = options.env

    local env_map = {}
    for _, item in ipairs(env_list) do
      local k, v = item:match("([^=]+)=(.*)")
      env_map[k] = v
    end

    assert.equals("testuser", env_map["USER"]) -- Inherited
    assert.equals("/home/override", env_map["HOME"]) -- Overridden
    assert.equals("/usr/bin:/bin", env_map["PATH"]) -- Inherited
  end)

  it("should add new environment variables", function()
    -- Mock environment
    environ_stub.returns({
      USER = "testuser",
    })

    -- Mock successful spawn
    spawn_stub.returns({}, 1234)

    local config = {
      transport_type = "stdio",
      command = "test-agent",
      args = {},
      env = {
        NEW_VAR = "new_value"
      }
    }

    local client = ACPClient:new(config)
    client:connect(function() end)

    assert.stub(spawn_stub).was_called(1)
    local call_args = spawn_stub.calls[1].refs
    local options = call_args[2]
    local env_list = options.env

    local env_map = {}
    for _, item in ipairs(env_list) do
      local k, v = item:match("([^=]+)=(.*)")
      env_map[k] = v
    end

    assert.equals("testuser", env_map["USER"])
    assert.equals("new_value", env_map["NEW_VAR"])
  end)

  it("should delete inherited environment variables when overridden with nil", function()
    -- Mock environment
    environ_stub.returns({
      USER = "testuser",
      HOME = "/home/testuser",
      TO_BE_REMOVED = "remove_me"
    })

    -- Mock successful spawn
    spawn_stub.returns({}, 1234)

    local config = {
      transport_type = "stdio",
      command = "test-agent",
      args = {},
      env = {
        TO_BE_REMOVED = vim.NIL
      }
    }

    local client = ACPClient:new(config)
    client:connect(function() end)

    assert.stub(spawn_stub).was_called(1)
    local call_args = spawn_stub.calls[1].refs
    local options = call_args[2]
    local env_list = options.env

    local env_map = {}
    for _, item in ipairs(env_list) do
      local k, v = item:match("([^=]+)=(.*)")
      env_map[k] = v
    end

    assert.equals("testuser", env_map["USER"])
    assert.is_nil(env_map["TO_BE_REMOVED"])
  end)
end)
