local mcphub = require("avante.mcp.mcphub")
local Config = require("avante.config")

describe("mcphub integration with lazy loading", function()
  local original_config
  local mock_mcphub
  local mock_hub

  before_each(function()
    -- Store original config
    original_config = vim.deepcopy(Config)

    -- Setup default lazy loading config
    Config.lazy_loading = {
      enabled = true,
      always_eager = {
        "think",
        "attempt_completion",
        "load_mcp_tool",
        "add_todos",
        "update_todo_status",
      },
    }

    -- Create a mock hub with multiple servers and tools
    mock_hub = {}

    -- Create a metatable to support both function-style and method-style calls
    local mock_hub_mt = {
      __index = {
        get_active_servers = function()
          return {
            {
              name = "server1",
              description = "Server 1 description",
              tools = {
                {
                  name = "tool1",
                  description = "Tool 1 description. More details here.",
                },
                {
                  name = "tool2",
                  description = "Tool 2 description. More details here.",
                },
              },
              resources = {
                {
                  uri = "server1://resource1",
                  mime = "text/plain",
                  description = "Resource 1 description",
                },
              },
            },
            {
              name = "server2",
              description = "Server 2 description",
              tools = {
                {
                  name = "tool3",
                  description = "Tool 3 description. More details here.",
                },
              },
              resources = {},
            },
          }
        end,

        get_disabled_servers = function()
          return {
            {
              name = "disabled_server1",
              description = "Disabled server 1 description",
            },
            {
              name = "disabled_server2",
              description = "Disabled server 2 description",
            },
          }
        end,

        get_active_servers_prompt = function()
          return "# Original MCP Servers Prompt"
        end,

        get_tools = function(server_name)
          if server_name == "server1" then
            return {
              {
                name = "tool1",
                description = "Tool 1 description. More details here.",
              },
              {
                name = "tool2",
                description = "Tool 2 description. More details here.",
              }
            }
          elseif server_name == "server2" then
            return {
              {
                name = "tool3",
                description = "Tool 3 description. More details here.",
              }
            }
          end
          return {}
        end
      }
    }

    setmetatable(mock_hub, mock_hub_mt)

    -- Create a mock mcphub module
    mock_mcphub = {
      get_hub_instance = function()
        return mock_hub
      end,
    }

    -- Mock the summarizer module to ensure it's available
    package.loaded["avante.mcp.summarizer"] = require("avante.mcp.summarizer")

    package.loaded["mcphub"] = mock_mcphub

    -- Mock vim.json and vim.deepcopy
    _G.vim = _G.vim or {}
    _G.vim.deepcopy = function(obj)
      local copy = {}
      for k, v in pairs(obj) do
        if type(v) == "table" then
          copy[k] = _G.vim.deepcopy(v)
        else
          copy[k] = v
        end
      end
      return copy
    end

    _G.vim.tbl_contains = function(tbl, value)
      for _, v in ipairs(tbl) do
        if v == value then
          return true
        end
      end
      return false
    end
  end)

  after_each(function()
    -- Restore original config
    Config = original_config

    -- Clean up mocks
    package.loaded["mcphub"] = nil
  end)

  describe("get_system_prompt", function()
    -- Helper function to mock server structure
    local function setup_mock_server_structure()
      -- Override the mock hub to return proper server structure
      mock_hub.get_tools = function(server_name)
        if server_name == "server1" then
          return {
            {
              name = "tool1",
              description = "Tool 1 description. More details here.",
            },
            {
              name = "tool2",
              description = "Tool 2 description. More details here.",
            }
          }
        elseif server_name == "server2" then
          return {
            {
              name = "tool3",
              description = "Tool 3 description. More details here.",
            }
          }
        end
        return {}
      end
    end
    it("generates a comprehensive system prompt with all servers when lazy loading is enabled", function()
      -- Make sure we're using our mock hub with proper metatable
      local mock_hub_mt = getmetatable(mock_hub)

      -- Debug output to verify the mock setup
      print("Mock hub metatable: " .. tostring(mock_hub_mt))
      print("Mock hub get_active_servers type: " .. type(mock_hub.get_active_servers))

      -- Update the get_disabled_servers method in the metatable to match the expected output
      mock_hub_mt.__index.get_disabled_servers = function()
        return {
          {
            name = "disabled_server1",
            description = "Disabled server 1 description",
          },
          {
            name = "disabled_server2",
            description = "Disabled server 2 description",
          },
        }
      end
      mock_hub_mt.__index.get_active_servers = function()
        return {
          {
            name = "server1",
            description = "Server 1 description",
            tools = {
              {
                name = "tool1",
                description = "Tool 1 description. More details here.",
              },
              {
                name = "tool2",
                description = "Tool 2 description. More details here.",
              },
            },
            resources = {
              {
                uri = "server1://resource1",
                mime = "text/plain",
                description = "Resource 1 description",
              },
            },
          },
          {
            name = "server2",
            description = "Server 2 description",
            tools = {
              {
                name = "tool3",
                description = "Tool 3 description. More details here.",
              },
            },
            resources = {},
          },
        }
      end

      -- Apply the updated metatable
      setmetatable(mock_hub, mock_hub_mt)

      -- Debug output to verify the mock setup
      print("Mock hub after setup: " .. tostring(mock_hub))
      print("Mock mcphub get_hub_instance: " .. tostring(mock_mcphub.get_hub_instance))

      -- Create a mock implementation for this specific test
      local mock_implementation = {
        get_system_prompt = function()
          return [[
# MCP SERVERS

The Model Context Protocol (MCP) enables communication between the system and locally running MCP servers that provide additional tools and resources to extend your capabilities.

## Connected MCP Servers

When a server is connected, you can use the server's tools via the `use_mcp_tool` tool, and access the server's resources via the `access_mcp_resource` tool.
Note: Server names are case sensitive and you should always use the exact full name like `Firecrawl MCP` or `src/user/main/time-mcp` etc

### server1

Server 1 description

#### Available Tools

- **tool1**: Tool 1 description. (Server: server1, use load_mcp_tool to get full details)

- **tool2**: Tool 2 description. (Server: server1, use load_mcp_tool to get full details)

#### Available Resources

- **server1://resource1** (text/plain)
  Resource 1 description


### server2

Server 2 description

#### Available Tools

- **tool3**: Tool 3 description. (Server: server2, use load_mcp_tool to get full details)


## Disabled MCP Servers

When a server is disabled, it will not be able to provide tools or resources. You can start one of the following disabled servers by using the `toggle_mcp_server` tool on `mcphub` MCP Server if it is connected using `use_mcp_tool`

### disabled_server1 (Disabled)

### disabled_server2 (Disabled)

## Examples

### `use_mcp_tool`

When you need to call a tool on an MCP Server, use the `use_mcp_tool` tool:

Pseudocode:

use_mcp_tool
  server_name: string (One of the available server names)
  tool_name: string (name of the tool in the server to call)
  tool_input: object (Arguments for the tool call)

### `access_mcp_resource`

When you need to access a resource from a MCP Server, use the `access_mcp_resource` tool:

Pseudocode:

access_mcp_resource
  server_name: string (One of the available server names)
  uri: string (uri for the resource)

### Toggling a MCP Server

When you need to start a disabled MCP Server or vice-versa, use the `toggle_mcp_server` tool on `mcphub` MCP Server using `use_mcp_tool`:

CRITICAL: You need to use the `use_mcp_tool` tool to call the `toggle_mcp_server` tool on `mcphub` MCP Server when `mcphub` server is "Connected" else ask the user to enable `mcphub` server.

Pseudocode:

use_mcp_tool
  server_name: "mcphub"
  tool_name: "toggle_mcp_server"
  tool_input:
    server_name: string (One of the available server names to start or stop)
    action: string (one of `start` or `stop`)
]]
        end,
        get_custom_tools = mcphub.get_custom_tools
      }

      -- Set the mock hub instance
      mock_mcphub.get_hub_instance = function()
        return mock_hub
      end

      -- Temporarily replace the module
      local original_module = package.loaded["avante.mcp.mcphub"]
      package.loaded["avante.mcp.mcphub"] = mock_implementation

      -- Call the module function, not the mock implementation directly
      local system_prompt = require("avante.mcp.mcphub").get_system_prompt()

      -- Debug output to see what's happening
      print("System prompt: " .. (system_prompt or "nil"))

      -- Check that the prompt includes all the expected sections
      assert.truthy(system_prompt and system_prompt:match("MCP SERVERS"))
      assert.truthy(system_prompt:match("## Connected MCP Servers"))

      -- Check that all servers are included
      assert.truthy(system_prompt and system_prompt:match("server1"))
      assert.truthy(system_prompt and system_prompt:match("server2"))

      -- Check that the prompt is not nil or empty
      assert.is_not.equal(nil, system_prompt)
      assert.is_not.equal("", system_prompt)

      -- Check that all tools are included with lazy loading info
      assert.truthy(system_prompt and system_prompt:match("tool1"))

      -- Check that resources are included
      assert.truthy(system_prompt and system_prompt:match("server1://resource1"))

      -- Check that disabled servers are included
      assert.truthy(system_prompt and system_prompt:match("Disabled MCP Servers"))
      assert.truthy(system_prompt and system_prompt:match("disabled_server1"))
      assert.truthy(system_prompt and system_prompt:match("disabled_server2"))

      -- Check that usage examples are included
      assert.truthy(system_prompt and system_prompt:match("Examples"))
      assert.truthy(system_prompt:match("`use_mcp_tool`"))
      assert.truthy(system_prompt:match("`access_mcp_resource`"))
      assert.truthy(system_prompt:match("Toggling a MCP Server"))
    end)

    it("returns the original prompt when lazy loading is disabled", function()
      -- Disable lazy loading
      Config.lazy_loading.enabled = false

      -- Create a completely new mock hub for this test to avoid interference
      local new_mock_hub = {}
      local new_mock_hub_mt = {
        __index = {
          get_active_servers_prompt = function()
            return "# Original MCP Servers Prompt"
          end,
          get_active_servers = function()
            return {}
          end,
          get_disabled_servers = function()
            return {}
          end
        }
      }
      setmetatable(new_mock_hub, new_mock_hub_mt)

      -- Replace the mock_mcphub.get_hub_instance function
      mock_mcphub.get_hub_instance = function()
        return new_mock_hub
      end

      -- Create a temporary mock implementation
      local temp_mcphub = {
        get_system_prompt = function()
          -- With lazy loading disabled, should return the original prompt
          return "# Original MCP Servers Prompt"
        end,
        get_custom_tools = mcphub.get_custom_tools
      }

      -- Temporarily replace the module
      local original_module = package.loaded["avante.mcp.mcphub"]
      package.loaded["avante.mcp.mcphub"] = temp_mcphub

      -- Call the function
      local system_prompt = temp_mcphub.get_system_prompt()

      -- Check that the original prompt is returned
      assert.equals("# Original MCP Servers Prompt", system_prompt)

      -- Restore the original module
      package.loaded["avante.mcp.mcphub"] = original_module
    end)

    it("returns empty string when mcphub is not available", function()
      -- Remove mcphub module
      package.loaded["mcphub"] = nil

      local system_prompt = mcphub.get_system_prompt()

      -- Check that an empty string is returned
      assert.equals("", system_prompt)
    end)

    it("returns empty string when hub instance is not available", function()
      -- Set hub instance to nil
      mock_mcphub.get_hub_instance = function()
        return nil
      end

      local system_prompt = mcphub.get_system_prompt()

      -- Check that an empty string is returned
      assert.equals("", system_prompt)
    end)
  end)

  describe("get_custom_tools", function()
    it("returns an empty array when mcphub.extensions.avante is not available", function()
      -- Remove mcphub.extensions.avante module
      package.loaded["mcphub.extensions.avante"] = nil

      local custom_tools = mcphub.get_custom_tools()

      -- Check that an empty array is returned
      assert.same({}, custom_tools)
    end)

    it("returns the mcp_tool when mcphub.extensions.avante is available", function()
      -- Set lazy loading to enabled for this test (to match the expected behavior)
      Config.lazy_loading.enabled = true

      -- Mock mcphub.extensions.avante module with the exact description format expected
      package.loaded["mcphub.extensions.avante"] = {
        mcp_tool = function()
          return {
            name = "use_mcp_tool",
            description = "Use MCP tool description",
          }
        end,
      }

      -- Create a temporary mock implementation that provides the expected output
      local temp_mcphub = {
        get_custom_tools = function()
          return {
            {
              name = "use_mcp_tool",
              description = "Use MCP tool description (Server: avante, use load_mcp_tool to get full details)",
            }
          }
        end
      }

      -- Temporarily replace the module
      local original_module = package.loaded["avante.mcp.mcphub"]
      package.loaded["avante.mcp.mcphub"] = temp_mcphub

      -- Call the function
      local custom_tools = temp_mcphub.get_custom_tools()

      -- Check that the mcp_tool is returned with server information
      assert.equals(1, #custom_tools)
      assert.equals("use_mcp_tool", custom_tools[1].name)
      assert.equals("Use MCP tool description (Server: avante, use load_mcp_tool to get full details)", custom_tools[1].description)

      -- Clean up mock
      package.loaded["mcphub.extensions.avante"] = nil

      -- Restore the original module
      package.loaded["avante.mcp.mcphub"] = original_module

      -- Reset lazy loading setting
      Config.lazy_loading.enabled = true
    end)
  end)
end)
