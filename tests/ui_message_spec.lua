local UIMessage = require("avante.ui_message")

describe("UIMessage", function()
  local sample_uuid = "test-uuid-123"

  describe("constructor", function()
    it("should create a new UIMessage with defaults", function()
      local msg = UIMessage:new(sample_uuid)

      assert.equals(sample_uuid, msg.uuid)
      assert.is_nil(msg.displayed_content)
      assert.equals(true, msg.visible)
      assert.equals(false, msg.is_dummy)
      assert.equals(false, msg.just_for_display)
      assert.equals(false, msg.is_calling)
      assert.equals("generated", msg.state)
      assert.same({}, msg.ui_cache)
      assert.same({}, msg.rendering_metadata)
      assert.equals(0, msg.last_rendered_at)
      assert.is_nil(msg.computed_lines)
    end)

    it("should create UIMessage with options", function()
      local opts = {
        displayed_content = "Custom display",
        visible = false,
        is_dummy = true,
        just_for_display = true,
        is_calling = true,
        state = "generating",
      }
      
      local msg = UIMessage:new(sample_uuid, opts)

      assert.equals(sample_uuid, msg.uuid)
      assert.equals("Custom display", msg.displayed_content)
      assert.equals(false, msg.visible)
      assert.equals(true, msg.is_dummy)
      assert.equals(true, msg.just_for_display)
      assert.equals(true, msg.is_calling)
      assert.equals("generating", msg.state)
    end)
  end)

  describe("synthetic messages", function()
    it("should create synthetic UIMessage", function()
      local opts = {
        displayed_content = "Synthetic content"
      }
      
      local msg = UIMessage:new_synthetic(sample_uuid, opts)

      assert.equals(sample_uuid, msg.uuid)
      assert.equals("Synthetic content", msg.displayed_content)
      assert.equals(true, msg.is_dummy)
    end)
  end)

  describe("state management", function()
    local msg

    before_each(function()
      msg = UIMessage:new(sample_uuid)
    end)

    it("should update visibility", function()
      msg:set_visible(false)
      assert.equals(false, msg.visible)
      
      msg:set_visible(true)
      assert.equals(true, msg.visible)
    end)

    it("should update calling state", function()
      msg:set_calling(true)
      assert.equals(true, msg.is_calling)
      
      msg:set_calling(false)
      assert.equals(false, msg.is_calling)
    end)

    it("should update displayed content and clear cache", function()
      -- Set up some cached data
      msg.computed_lines = { "cached line" }
      msg.last_rendered_at = 12345
      
      msg:set_displayed_content("New content")

      assert.equals("New content", msg.displayed_content)
      assert.is_nil(msg.computed_lines)
      assert.equals(0, msg.last_rendered_at)
    end)

    it("should update state and sync calling flag", function()
      msg:set_state("generating")
      
      assert.equals("generating", msg.state)
      assert.equals(true, msg.is_calling)
      
      msg:set_state("generated")
      
      assert.equals("generated", msg.state)
      assert.equals(false, msg.is_calling)
    end)
  end)

  describe("cache management", function()
    local msg

    before_each(function()
      msg = UIMessage:new(sample_uuid)
    end)

    it("should validate cache correctly", function()
      -- No cached lines initially
      assert.equals(false, msg:is_cache_valid())
      
      -- Add cached lines
      msg.computed_lines = { "line1", "line2" }
      msg.last_rendered_at = os.time()
      
      assert.equals(true, msg:is_cache_valid())
    end)

    it("should invalidate cache with newer model timestamp", function()
      msg.computed_lines = { "line1" }
      msg.last_rendered_at = 1000
      
      -- Cache is valid for older or same timestamp
      assert.equals(true, msg:is_cache_valid("999"))
      assert.equals(true, msg:is_cache_valid("1000"))
      
      -- Cache is invalid for newer timestamp
      assert.equals(false, msg:is_cache_valid("1001"))
    end)

    it("should invalidate cache manually", function()
      msg.computed_lines = { "line1" }
      msg.ui_cache = { key = "value" }
      msg.last_rendered_at = 12345
      
      msg:invalidate_cache()

      assert.is_nil(msg.computed_lines)
      assert.same({}, msg.ui_cache)
      assert.equals(0, msg.last_rendered_at)
    end)

    it("should update cache", function()
      local test_lines = { "line1", "line2", "line3" }
      local before_time = os.time()
      
      msg:update_cache(test_lines)

      assert.same(test_lines, msg.computed_lines)
      assert.is_true(msg.last_rendered_at >= before_time)
    end)

    it("should get cached lines when valid", function()
      local test_lines = { "cached1", "cached2" }
      msg.computed_lines = test_lines
      msg.last_rendered_at = os.time()
      
      local result = msg:get_cached_lines()
      assert.same(test_lines, result)
      
      -- Should return nil when cache is invalid
      msg.computed_lines = nil
      result = msg:get_cached_lines()
      assert.is_nil(result)
    end)

    it("should respect model timestamp in cached lines", function()
      local test_lines = { "line1" }
      msg.computed_lines = test_lines
      msg.last_rendered_at = 1000
      
      -- Valid for older model timestamp
      local result = msg:get_cached_lines("999")
      assert.same(test_lines, result)
      
      -- Invalid for newer model timestamp
      result = msg:get_cached_lines("1001")
      assert.is_nil(result)
    end)
  end)

  describe("metadata management", function()
    local msg

    before_each(function()
      msg = UIMessage:new(sample_uuid)
    end)

    it("should set and get rendering metadata", function()
      msg:set_rendering_metadata("highlight", "error")
      msg:set_rendering_metadata("indent", 4)
      
      assert.equals("error", msg:get_rendering_metadata("highlight"))
      assert.equals(4, msg:get_rendering_metadata("indent"))
      assert.is_nil(msg:get_rendering_metadata("nonexistent"))
    end)

    it("should set and get UI cache values", function()
      msg:set_ui_cache("processed_content", "cached content")
      msg:set_ui_cache("line_count", 42)
      
      assert.equals("cached content", msg:get_ui_cache("processed_content"))
      assert.equals(42, msg:get_ui_cache("line_count"))
      assert.is_nil(msg:get_ui_cache("missing"))
    end)

    it("should store complex metadata", function()
      local complex_data = {
        styles = { "bold", "italic" },
        positions = { start = 1, finish = 10 }
      }
      
      msg:set_rendering_metadata("formatting", complex_data)
      
      local retrieved = msg:get_rendering_metadata("formatting")
      assert.same(complex_data, retrieved)
    end)
  end)
end)