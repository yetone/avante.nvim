local Utils = require("avante.utils")

describe("Utils", function()
  describe("trim", function()
    it("should trim prefix", function() assert.equals("test", Utils.trim("prefix_test", { prefix = "prefix_" })) end)

    it("should trim suffix", function() assert.equals("test", Utils.trim("test_suffix", { suffix = "_suffix" })) end)

    it(
      "should trim both prefix and suffix",
      function() assert.equals("test", Utils.trim("prefix_test_suffix", { prefix = "prefix_", suffix = "_suffix" })) end
    )

    it(
      "should return original string if no match",
      function() assert.equals("test", Utils.trim("test", { prefix = "xxx", suffix = "yyy" })) end
    )
  end)

  describe("url_join", function()
    it("should join url parts correctly", function()
      assert.equals("http://example.com/path", Utils.url_join("http://example.com", "path"))
      assert.equals("http://example.com/path", Utils.url_join("http://example.com/", "/path"))
      assert.equals("http://example.com/path/to", Utils.url_join("http://example.com", "path", "to"))
      assert.equals("http://example.com/path", Utils.url_join("http://example.com/", "/path/"))
    end)

    it("should handle empty parts", function()
      assert.equals("http://example.com", Utils.url_join("http://example.com", ""))
      assert.equals("http://example.com", Utils.url_join("http://example.com", nil))
    end)
  end)

  describe("is_type", function()
    it("should check basic types correctly", function()
      assert.is_true(Utils.is_type("string", "test"))
      assert.is_true(Utils.is_type("number", 123))
      assert.is_true(Utils.is_type("boolean", true))
      assert.is_true(Utils.is_type("table", {}))
      assert.is_true(Utils.is_type("function", function() end))
      assert.is_true(Utils.is_type("nil", nil))
    end)

    it("should check list type correctly", function()
      assert.is_true(Utils.is_type("list", { 1, 2, 3 }))
      assert.is_false(Utils.is_type("list", { a = 1, b = 2 }))
    end)

    it("should check map type correctly", function()
      assert.is_true(Utils.is_type("map", { a = 1, b = 2 }))
      assert.is_false(Utils.is_type("map", { 1, 2, 3 }))
    end)
  end)

  describe("get_indentation", function()
    it("should get correct indentation", function()
      assert.equals("  ", Utils.get_indentation("  test"))
      assert.equals("\t", Utils.get_indentation("\ttest"))
      assert.equals("", Utils.get_indentation("test"))
    end)

    it("should handle empty or nil input", function()
      assert.equals("", Utils.get_indentation(""))
      assert.equals("", Utils.get_indentation(nil))
    end)
  end)

  describe("remove_indentation", function()
    it("should remove indentation correctly", function()
      assert.equals("test", Utils.remove_indentation("  test"))
      assert.equals("test", Utils.remove_indentation("\ttest"))
      assert.equals("test", Utils.remove_indentation("test"))
    end)

    it("should handle empty or nil input", function()
      assert.equals("", Utils.remove_indentation(""))
      assert.equals(nil, Utils.remove_indentation(nil))
    end)
  end)

  describe("is_first_letter_uppercase", function()
    it("should detect uppercase first letter", function()
      assert.is_true(Utils.is_first_letter_uppercase("Test"))
      assert.is_true(Utils.is_first_letter_uppercase("ABC"))
    end)

    it("should detect lowercase first letter", function()
      assert.is_false(Utils.is_first_letter_uppercase("test"))
      assert.is_false(Utils.is_first_letter_uppercase("abc"))
    end)
  end)

  describe("extract_mentions", function()
    it("should extract @codebase mention", function()
      local result = Utils.extract_mentions("test @codebase")
      assert.equals("test ", result.new_content)
      assert.is_true(result.enable_project_context)
      assert.is_false(result.enable_diagnostics)
    end)

    it("should extract @diagnostics mention", function()
      local result = Utils.extract_mentions("test @diagnostics")
      assert.equals("test @diagnostics", result.new_content)
      assert.is_false(result.enable_project_context)
      assert.is_true(result.enable_diagnostics)
    end)

    it("should handle multiple mentions", function()
      local result = Utils.extract_mentions("test @codebase @diagnostics")
      assert.equals("test  @diagnostics", result.new_content)
      assert.is_true(result.enable_project_context)
      assert.is_true(result.enable_diagnostics)
    end)
  end)

  describe("get_mentions", function()
    it("should return valid mentions", function()
      local mentions = Utils.get_mentions()
      assert.equals("codebase", mentions[1].command)
      assert.equals("diagnostics", mentions[2].command)
    end)
  end)
end)
