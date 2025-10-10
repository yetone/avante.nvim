local ConfirmAdapter = require("avante.ui.acp_confirm_adapter")

describe("ConfirmAdapter (ACP)", function()
  describe("map_acp_options", function()
    it("should map allow_once to yes button", function()
      local options = { { kind = "allow_once", optionId = "opt1", name = "Allow Once" } }
      local result = ConfirmAdapter.map_acp_options(options)

      assert.is_true(result.has_allow_once)
      assert.equals("opt1", result.option_map.yes)
    end)

    it("should map allow_always to all button", function()
      local options = { { kind = "allow_always", optionId = "opt2", name = "Allow Always" } }
      local result = ConfirmAdapter.map_acp_options(options)

      assert.is_true(result.has_allow_always)
      assert.equals("opt2", result.option_map.all)
    end)

    it("should map reject_once to no button", function()
      local options = { { kind = "reject_once", optionId = "opt3", name = "Reject" } }
      local result = ConfirmAdapter.map_acp_options(options)

      assert.is_true(result.has_reject)
      assert.equals("opt3", result.option_map.no)
    end)

    it("should map reject_always to no button", function()
      local options = { { kind = "reject_always", optionId = "opt4", name = "Reject Always" } }
      local result = ConfirmAdapter.map_acp_options(options)

      assert.is_true(result.has_reject)
      assert.equals("opt4", result.option_map.no)
    end)

    it("should handle multiple options", function()
      local options = {
        { kind = "allow_once", optionId = "opt1", name = "Allow Once" },
        { kind = "allow_always", optionId = "opt2", name = "Allow Always" },
        { kind = "reject_once", optionId = "opt3", name = "Reject" },
      }
      local result = ConfirmAdapter.map_acp_options(options)

      assert.is_true(result.has_allow_once)
      assert.is_true(result.has_allow_always)
      assert.is_true(result.has_reject)
      assert.equals("opt1", result.option_map.yes)
      assert.equals("opt2", result.option_map.all)
      assert.equals("opt3", result.option_map.no)
    end)

    it("should prefer first allow_once when multiple exist", function()
      local options = {
        { kind = "allow_once", optionId = "opt1", name = "Allow Once" },
        { kind = "allow_once", optionId = "opt2", name = "Allow Once Again" },
      }
      local result = ConfirmAdapter.map_acp_options(options)

      assert.equals("opt1", result.option_map.yes)
    end)

    it("should prefer first reject option when multiple exist", function()
      local options = {
        { kind = "reject_once", optionId = "opt1", name = "Reject" },
        { kind = "reject_always", optionId = "opt2", name = "Reject Always" },
      }
      local result = ConfirmAdapter.map_acp_options(options)

      assert.equals("opt1", result.option_map.no)
    end)

    it("should handle empty options array", function()
      local result = ConfirmAdapter.map_acp_options({})

      assert.is_false(result.has_allow_once)
      assert.is_false(result.has_allow_always)
      assert.is_false(result.has_reject)
      assert.is_nil(result.option_map.yes)
      assert.is_nil(result.option_map.all)
      assert.is_nil(result.option_map.no)
    end)

    it("should handle only allow_once option (no all button)", function()
      local options = {
        { kind = "allow_once", optionId = "opt1", name = "Allow Once" },
        { kind = "reject_once", optionId = "opt2", name = "Reject" },
      }
      local result = ConfirmAdapter.map_acp_options(options)

      assert.is_true(result.has_allow_once)
      assert.is_false(result.has_allow_always)
      assert.is_true(result.has_reject)
    end)

    it("should handle unknown option kinds gracefully", function()
      local options = {
        { kind = "unknown_kind", optionId = "opt1", name = "Unknown" },
        { kind = "allow_once", optionId = "opt2", name = "Allow Once" },
      }
      local result = ConfirmAdapter.map_acp_options(options)

      -- Unknown kinds should be ignored
      assert.is_true(result.has_allow_once)
      assert.equals("opt2", result.option_map.yes)
    end)
  end)

  describe("create_acp_callback_bridge", function()
    it("should translate yes to allow_once option id", function()
      local called_option_id = nil
      local acp_callback = function(id) called_option_id = id end
      local option_map = { yes = "opt1", all = "opt2", no = "opt3" }

      local bridge = ConfirmAdapter.create_acp_callback_bridge(acp_callback, option_map)
      bridge("yes")

      assert.equals("opt1", called_option_id)
    end)

    it("should translate all to allow_always option id", function()
      local called_option_id = nil
      local acp_callback = function(id) called_option_id = id end
      local option_map = { yes = "opt1", all = "opt2", no = "opt3" }

      local bridge = ConfirmAdapter.create_acp_callback_bridge(acp_callback, option_map)
      bridge("all")

      assert.equals("opt2", called_option_id)
    end)

    it("should translate no to nil (cancelled outcome)", function()
      local called_option_id = "not_nil"
      local acp_callback = function(id) called_option_id = id end
      local option_map = { yes = "opt1", all = "opt2", no = "opt3" }

      local bridge = ConfirmAdapter.create_acp_callback_bridge(acp_callback, option_map)
      bridge("no")

      assert.is_nil(called_option_id)
    end)

    it("should handle missing option with fallback to yes", function()
      local called_option_id = nil
      local acp_callback = function(id) called_option_id = id end
      local option_map = { yes = "opt1", no = "opt3" } -- missing 'all'

      local bridge = ConfirmAdapter.create_acp_callback_bridge(acp_callback, option_map)
      bridge("all") -- try to use missing 'all'

      -- Should fallback to 'yes'
      assert.equals("opt1", called_option_id)
    end)

    it("should handle missing yes option with fallback to cancel", function()
      local called_option_id = "not_nil"
      local acp_callback = function(id) called_option_id = id end
      local option_map = { no = "opt3" } -- missing 'yes' and 'all'

      local bridge = ConfirmAdapter.create_acp_callback_bridge(acp_callback, option_map)
      bridge("yes") -- try to use missing 'yes'

      -- Should fallback to nil (cancel)
      assert.is_nil(called_option_id)
    end)

    it("should cancel if no options available", function()
      local called_option_id = "not_nil"
      local acp_callback = function(id) called_option_id = id end
      local option_map = {} -- empty

      local bridge = ConfirmAdapter.create_acp_callback_bridge(acp_callback, option_map)
      bridge("yes")

      -- Should send nil (cancelled)
      assert.is_nil(called_option_id)
    end)
  end)

  describe("get_acp_message", function()
    it("should format read tool call as readable message", function()
      local tool_call = {
        kind = "read",
        title = "Read config.lua",
      }

      local message = ConfirmAdapter.get_acp_message(tool_call)

      assert.is_not_nil(string.find(message, "read"))
      assert.is_not_nil(string.find(message, "Read config.lua"))
    end)

    it("should format edit tool call as readable message", function()
      local tool_call = {
        kind = "edit",
        title = "Edit main.lua",
      }

      local message = ConfirmAdapter.get_acp_message(tool_call)

      assert.is_not_nil(string.find(message, "edit"))
      assert.is_not_nil(string.find(message, "Edit main.lua"))
    end)

    it("should format delete tool call as readable message", function()
      local tool_call = {
        kind = "delete",
        title = "Delete temp.txt",
      }

      local message = ConfirmAdapter.get_acp_message(tool_call)

      assert.is_not_nil(string.find(message, "delete"))
      assert.is_not_nil(string.find(message, "Delete temp.txt"))
    end)

    it("should format execute tool call as readable message", function()
      local tool_call = {
        kind = "execute",
        title = "npm install",
      }

      local message = ConfirmAdapter.get_acp_message(tool_call)

      assert.is_not_nil(string.find(message, "execute"))
      assert.is_not_nil(string.find(message, "npm install"))
    end)

    it("should handle unknown tool kind with default action", function()
      local tool_call = {
        kind = "unknown_action",
        title = "Some action",
      }

      local message = ConfirmAdapter.get_acp_message(tool_call)

      assert.is_not_nil(string.find(message, "perform"))
      assert.is_not_nil(string.find(message, "Some action"))
    end)

    it("should handle missing title gracefully", function()
      local tool_call = {
        kind = "read",
      }

      local message = ConfirmAdapter.get_acp_message(tool_call)

      -- Should still produce a valid message even without title
      assert.is_not_nil(message)
      assert.is_not_nil(string.find(message, "read"))
    end)

    it("should format all supported tool kinds", function()
      local kinds = { "read", "edit", "delete", "move", "search", "execute", "fetch" }

      for _, kind in ipairs(kinds) do
        local tool_call = {
          kind = kind,
          title = "Test " .. kind,
        }

        local message = ConfirmAdapter.get_acp_message(tool_call)

        assert.is_not_nil(string.find(message, kind))
        assert.is_not_nil(string.find(message, "Test " .. kind))
      end
    end)
  end)
end)
