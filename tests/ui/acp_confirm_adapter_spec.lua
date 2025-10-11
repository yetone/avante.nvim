local ACPConfirmAdapter = require("avante.ui.acp_confirm_adapter")

describe("ACPConfirmAdapter", function()
  describe("map_acp_options", function()
    it("should ignore reject_always", function()
      local options = { { kind = "reject_always", optionId = "opt4" } }
      local result = ACPConfirmAdapter.map_acp_options(options)
      assert.is_nil(result.yes)
      assert.is_nil(result.all)
      assert.is_nil(result.no)
    end)

    it("should map multiple options correctly", function()
      local options = {
        { kind = "allow_once", optionId = "yes_id" },
        { kind = "allow_always", optionId = "all_id" },
        { kind = "reject_once", optionId = "no_id" },
        { kind = "reject_always", optionId = "ignored_id" },
      }
      local result = ACPConfirmAdapter.map_acp_options(options)
      assert.equals("yes_id", result.yes)
      assert.equals("all_id", result.all)
      assert.equals("no_id", result.no)
    end)

    it("should handle empty options", function()
      local options = {}
      local result = ACPConfirmAdapter.map_acp_options(options)
      assert.is_nil(result.yes)
      assert.is_nil(result.all)
      assert.is_nil(result.no)
    end)
  end)
end)
