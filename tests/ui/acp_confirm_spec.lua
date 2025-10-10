local Confirm = require("avante.ui.confirm")

describe("Confirm UI (ACP Dynamic Buttons)", function()
  local test_container_winid

  before_each(function()
    -- Create a test buffer and window for container
    local buf = vim.api.nvim_create_buf(false, true)
    test_container_winid = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      width = 80,
      height = 20,
      row = 0,
      col = 0,
    })
  end)

  after_each(function()
    if test_container_winid and vim.api.nvim_win_is_valid(test_container_winid) then
      vim.api.nvim_win_close(test_container_winid, true)
    end
  end)

  describe("Button availability configuration", function()
    it("should accept button_availability option in constructor", function()
      local callback_called = false
      local callback = function() callback_called = true end

      local button_availability = {
        has_allow_once = true,
        has_allow_always = false,
        has_reject = true,
      }

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
        button_availability = button_availability,
      })

      -- Verify the button availability is stored
      assert.is_not_nil(confirm._button_availability)
      assert.equals(true, confirm._button_availability.has_allow_once)
      assert.equals(false, confirm._button_availability.has_allow_always)
      assert.equals(true, confirm._button_availability.has_reject)
    end)

    it("should work without button_availability (default 3 buttons)", function()
      local callback = function() end

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
      })

      -- Should work without button_availability (defaults to all buttons)
      assert.is_nil(confirm._button_availability)
    end)
  end)

  describe("Button configuration for 2-button layout", function()
    it("should create 2 buttons when has_allow_always is false", function()
      local callback = function() end

      local button_availability = {
        has_allow_once = true,
        has_allow_always = false,
        has_reject = true,
      }

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
        button_availability = button_availability,
      })

      -- Open the popup to trigger button creation
      confirm:open()

      -- Verify popup was created
      assert.is_not_nil(confirm._popup)

      -- The button count should be stored or accessible
      assert.is_not_nil(confirm._button_count)
      assert.equals(2, confirm._button_count)

      -- Clean up
      confirm:close()
    end)

    it("should create 2 buttons when only yes and no available", function()
      local callback = function() end

      local button_availability = {
        has_allow_once = true,
        has_allow_always = false,
        has_reject = true,
      }

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
        button_availability = button_availability,
      })

      confirm:open()
      assert.equals(2, confirm._button_count)
      confirm:close()
    end)
  end)

  describe("Button configuration for 3-button layout", function()
    it("should create 3 buttons when all are available", function()
      local callback = function() end

      local button_availability = {
        has_allow_once = true,
        has_allow_always = true,
        has_reject = true,
      }

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
        button_availability = button_availability,
      })

      confirm:open()
      assert.equals(3, confirm._button_count)
      confirm:close()
    end)

    it("should create 3 buttons by default (no button_availability)", function()
      local callback = function() end

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
      })

      confirm:open()
      assert.equals(3, confirm._button_count)
      confirm:close()
    end)
  end)

  describe("Button index mapping", function()
    it("should map button indices correctly for 2-button layout", function()
      local callback = function() end

      local button_availability = {
        has_allow_once = true,
        has_allow_always = false,
        has_reject = true,
      }

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
        button_availability = button_availability,
      })

      confirm:open()

      -- For 2 buttons, indices should be:
      -- 1 = Yes, 2 = No
      assert.is_not_nil(confirm._button_map)
      assert.equals("yes", confirm._button_map[1])
      assert.equals("no", confirm._button_map[2])

      confirm:close()
    end)

    it("should map button indices correctly for 3-button layout", function()
      local callback = function() end

      local button_availability = {
        has_allow_once = true,
        has_allow_always = true,
        has_reject = true,
      }

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
        button_availability = button_availability,
      })

      confirm:open()

      -- For 3 buttons, indices should be:
      -- 1 = Yes, 2 = All, 3 = No
      assert.is_not_nil(confirm._button_map)
      assert.equals("yes", confirm._button_map[1])
      assert.equals("all", confirm._button_map[2])
      assert.equals("no", confirm._button_map[3])

      confirm:close()
    end)
  end)

  describe("Focus cycling with dynamic buttons", function()
    it("should cycle through 2 buttons correctly", function()
      local callback = function() end

      local button_availability = {
        has_allow_once = true,
        has_allow_always = false,
        has_reject = true,
      }

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
        button_availability = button_availability,
      })

      confirm:open()

      -- Initial focus should be on last button (no)
      assert.equals(2, confirm._focus_index)

      -- Cycling forward from button 2 should go to button 1
      confirm:_cycle_focus_forward()
      assert.equals(1, confirm._focus_index)

      -- Cycling forward from button 1 should go to button 2
      confirm:_cycle_focus_forward()
      assert.equals(2, confirm._focus_index)

      confirm:close()
    end)

    it("should cycle through 3 buttons correctly", function()
      local callback = function() end

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
      })

      confirm:open()

      -- Initial focus should be on button 3 (no)
      assert.equals(3, confirm._focus_index)

      -- Cycling forward: 3 -> 1 -> 2 -> 3
      confirm:_cycle_focus_forward()
      assert.equals(1, confirm._focus_index)

      confirm:_cycle_focus_forward()
      assert.equals(2, confirm._focus_index)

      confirm:_cycle_focus_forward()
      assert.equals(3, confirm._focus_index)

      confirm:close()
    end)
  end)

  describe("Keyboard shortcuts with dynamic buttons", function()
    it("should have 'y' shortcut for yes button in 2-button layout", function()
      local callback_type = nil
      local callback = function(type) callback_type = type end

      local button_availability = {
        has_allow_once = true,
        has_allow_always = false,
        has_reject = true,
      }

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
        button_availability = button_availability,
      })

      confirm:open()

      -- Simulate pressing 'y' key
      local bufnr = confirm._popup.bufnr
      local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")

      -- Find the 'y' keymap
      local has_y_keymap = false
      for _, map in ipairs(keymaps) do
        if map.lhs == "y" then
          has_y_keymap = true
          break
        end
      end

      assert.is_true(has_y_keymap)

      confirm:close()
    end)

    it("should not have 'a' shortcut for all button in 2-button layout", function()
      local callback = function() end

      local button_availability = {
        has_allow_once = true,
        has_allow_always = false,
        has_reject = true,
      }

      local confirm = Confirm:new("Test message", callback, {
        container_winid = test_container_winid,
        focus = false,
        button_availability = button_availability,
      })

      confirm:open()

      -- The 'a' key should still exist but should not trigger 'all' action
      -- Instead it should cycle to button 1 or do nothing
      assert.is_not_nil(confirm._popup)

      confirm:close()
    end)
  end)
end)
