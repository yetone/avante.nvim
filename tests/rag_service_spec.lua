local mock = require("luassert.mock")
local match = require("luassert.match")

describe("RagService", function()
  local RagService
  local Config_mock

  before_each(function()
    -- Load the module before each test
    RagService = require("avante.rag_service")

    -- Setup common mocks
    Config_mock = mock(require("avante.config"), true)
    Config_mock.rag_service = { host_mount = "/home/user" }
  end)

  after_each(function()
    -- Clean up after each test
    package.loaded["avante.rag_service"] = nil
    mock.revert(Config_mock)
  end)

  describe("URI conversion functions", function()
    it("should convert URIs between host and container formats", function()
      -- Test both directions of conversion
      local host_uri = "file:///home/user/project/file.txt"
      local container_uri = "file:///host/project/file.txt"

      -- Host to container
      local result1 = RagService.to_container_uri(host_uri)
      assert.equals(container_uri, result1)

      -- Container to host
      local result2 = RagService.to_local_uri(container_uri)
      assert.equals(host_uri, result2)
    end)
  end)
end)
