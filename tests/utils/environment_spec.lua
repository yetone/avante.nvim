local EnvUtils = require("avante.utils.environment")

describe("EnvUtils", function()
  describe("resolve_env_overrides", function()
    it("should return nil when env_overrides is nil", function()
      local result = EnvUtils.resolve_env_overrides(nil, "/some/path")
      assert.is_nil(result)
    end)

    it("should return nil when env_overrides is empty", function()
      local result = EnvUtils.resolve_env_overrides({}, "/some/path")
      assert.is_nil(result)
    end)

    it("should return nil when no paths match", function()
      local env_overrides = {
        ["/projects/client-a"] = { API_KEY = "key-a" },
        ["/projects/client-b"] = { API_KEY = "key-b" },
      }
      local result = EnvUtils.resolve_env_overrides(env_overrides, "/different/path")
      assert.is_nil(result)
    end)

    it("should match exact path", function()
      local env_overrides = {
        ["/projects/client-a"] = { API_KEY = "key-a" },
        ["/projects/client-b"] = { API_KEY = "key-b" },
      }
      local result = EnvUtils.resolve_env_overrides(env_overrides, "/projects/client-a")
      assert.is_not_nil(result)
      assert.equals("key-a", result.API_KEY)
    end)

    it("should match path prefix (subdirectory)", function()
      local env_overrides = {
        ["/projects/client-a"] = { API_KEY = "key-a" },
      }
      local result = EnvUtils.resolve_env_overrides(env_overrides, "/projects/client-a/subdir/deep")
      assert.is_not_nil(result)
      assert.equals("key-a", result.API_KEY)
    end)

    it("should return most specific (longest) matching path", function()
      local env_overrides = {
        ["/projects"] = { API_KEY = "key-root" },
        ["/projects/client-a"] = { API_KEY = "key-a" },
        ["/projects/client-a/subproject"] = { API_KEY = "key-subproject" },
      }
      local result = EnvUtils.resolve_env_overrides(env_overrides, "/projects/client-a/subproject/deep/path")
      assert.is_not_nil(result)
      assert.equals("key-subproject", result.API_KEY)
    end)

    it("should handle paths with trailing slashes", function()
      local env_overrides = {
        ["/projects/client-a/"] = { API_KEY = "key-a" },
      }
      local result = EnvUtils.resolve_env_overrides(env_overrides, "/projects/client-a")
      assert.is_not_nil(result)
      assert.equals("key-a", result.API_KEY)
    end)

    it("should normalize relative paths to absolute", function()
      local current_file_dir = vim.fn.expand("%:p:h")
      local env_overrides = {
        [current_file_dir] = { API_KEY = "key-current" },
      }
      -- Using a relative path that resolves to current directory
      local result = EnvUtils.resolve_env_overrides(env_overrides, ".")
      assert.is_not_nil(result)
      assert.equals("key-current", result.API_KEY)
    end)

    it("should expand tilde (~) to home directory", function()
      local home = os.getenv("HOME") or vim.fn.expand("~")
      local env_overrides = {
        ["~/projects/test"] = { API_KEY = "key-home" },
      }
      -- Test with a path under home directory
      local test_path = home .. "/projects/test/subdir"
      local result = EnvUtils.resolve_env_overrides(env_overrides, test_path)
      assert.is_not_nil(result)
      assert.equals("key-home", result.API_KEY)
    end)

    it("should match tilde paths against actual home paths", function()
      local home = os.getenv("HOME") or vim.fn.expand("~")
      local env_overrides = {
        ["~/projects/client-a"] = { API_KEY = "key-a" },
        [home .. "/projects/client-b"] = { API_KEY = "key-b" },
      }
      -- Test with tilde path
      local result_a = EnvUtils.resolve_env_overrides(env_overrides, home .. "/projects/client-a")
      assert.is_not_nil(result_a)
      assert.equals("key-a", result_a.API_KEY)
      
      -- Test with absolute path
      local result_b = EnvUtils.resolve_env_overrides(env_overrides, home .. "/projects/client-b")
      assert.is_not_nil(result_b)
      assert.equals("key-b", result_b.API_KEY)
    end)

    it("should handle multiple environment variables in override", function()
      local env_overrides = {
        ["/projects/client-a"] = {
          API_KEY = "key-a",
          BASE_URL = "https://api-a.example.com",
          DEBUG = "true",
        },
      }
      local result = EnvUtils.resolve_env_overrides(env_overrides, "/projects/client-a")
      assert.is_not_nil(result)
      assert.equals("key-a", result.API_KEY)
      assert.equals("https://api-a.example.com", result.BASE_URL)
      assert.equals("true", result.DEBUG)
    end)
  end)

  describe("merge_env_with_overrides", function()
    it("should return base_env when env_overrides is nil", function()
      local base_env = { API_KEY = "default-key", OTHER = "value" }
      local result = EnvUtils.merge_env_with_overrides(base_env, nil, "/some/path", false)
      
      assert.is_not_nil(result)
      assert.equals("default-key", result.API_KEY)
      assert.equals("value", result.OTHER)
      -- Ensure it's a copy, not the same table
      assert.are_not.equal(base_env, result)
    end)

    it("should return base_env when env_overrides is empty", function()
      local base_env = { API_KEY = "default-key" }
      local result = EnvUtils.merge_env_with_overrides(base_env, {}, "/some/path", false)
      
      assert.is_not_nil(result)
      assert.equals("default-key", result.API_KEY)
    end)

    it("should return base_env when no paths match", function()
      local base_env = { API_KEY = "default-key", OTHER = "value" }
      local env_overrides = {
        ["/projects/client-a"] = { API_KEY = "key-a" },
      }
      local result = EnvUtils.merge_env_with_overrides(base_env, env_overrides, "/different/path", false)
      
      assert.is_not_nil(result)
      assert.equals("default-key", result.API_KEY)
      assert.equals("value", result.OTHER)
    end)

    it("should override matching keys from base_env", function()
      local base_env = {
        API_KEY = "default-key",
        OTHER = "value",
        KEEP_ME = "untouched",
      }
      local env_overrides = {
        ["/projects/client-a"] = {
          API_KEY = "key-a",
          OTHER = "overridden",
        },
      }
      local result = EnvUtils.merge_env_with_overrides(base_env, env_overrides, "/projects/client-a", false)
      
      assert.is_not_nil(result)
      assert.equals("key-a", result.API_KEY)
      assert.equals("overridden", result.OTHER)
      assert.equals("untouched", result.KEEP_ME)
    end)

    it("should add new keys from override that don't exist in base_env", function()
      local base_env = { API_KEY = "default-key" }
      local env_overrides = {
        ["/projects/client-a"] = {
          API_KEY = "key-a",
          NEW_VAR = "new-value",
          ANOTHER_VAR = "another-value",
        },
      }
      local result = EnvUtils.merge_env_with_overrides(base_env, env_overrides, "/projects/client-a", false)
      
      assert.is_not_nil(result)
      assert.equals("key-a", result.API_KEY)
      assert.equals("new-value", result.NEW_VAR)
      assert.equals("another-value", result.ANOTHER_VAR)
    end)

    it("should use most specific path when multiple paths match", function()
      local base_env = { API_KEY = "default-key" }
      local env_overrides = {
        ["/projects"] = { API_KEY = "key-root" },
        ["/projects/client-a"] = { API_KEY = "key-a" },
        ["/projects/client-a/subproject"] = { API_KEY = "key-subproject" },
      }
      local result = EnvUtils.merge_env_with_overrides(base_env, env_overrides, "/projects/client-a/subproject", false)
      
      assert.is_not_nil(result)
      assert.equals("key-subproject", result.API_KEY)
    end)

    it("should not modify the original base_env table", function()
      local base_env = { API_KEY = "default-key" }
      local env_overrides = {
        ["/projects/client-a"] = { API_KEY = "key-a" },
      }
      local result = EnvUtils.merge_env_with_overrides(base_env, env_overrides, "/projects/client-a", false)
      
      -- Original should be unchanged
      assert.equals("default-key", base_env.API_KEY)
      -- Result should have override
      assert.equals("key-a", result.API_KEY)
    end)

    it("should handle empty base_env", function()
      local base_env = {}
      local env_overrides = {
        ["/projects/client-a"] = {
          API_KEY = "key-a",
          BASE_URL = "https://api-a.example.com",
        },
      }
      local result = EnvUtils.merge_env_with_overrides(base_env, env_overrides, "/projects/client-a", false)
      
      assert.is_not_nil(result)
      assert.equals("key-a", result.API_KEY)
      assert.equals("https://api-a.example.com", result.BASE_URL)
    end)

    it("should work with tilde expansion in overrides", function()
      local home = os.getenv("HOME") or vim.fn.expand("~")
      local base_env = { API_KEY = "default-key" }
      local env_overrides = {
        ["~/projects/client-a"] = { API_KEY = "key-a" },
      }
      local result = EnvUtils.merge_env_with_overrides(base_env, env_overrides, home .. "/projects/client-a", false)
      
      assert.is_not_nil(result)
      assert.equals("key-a", result.API_KEY)
    end)
  end)
end)