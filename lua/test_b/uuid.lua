-- UUID Generation Utility Module
-- Provides UUID v4 generation for unique identifiers

local M = {}

-- Generate a random UUID v4
-- @return string UUID in format xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
function M.generate()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

  -- Use vim's rng for random number generation if available
  local random = math.random
  if vim and vim.loop then
    -- Seed with high resolution time for better randomness
    math.randomseed(vim.loop.hrtime())
  else
    math.randomseed(os.time())
  end

  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and random(0, 15) or random(8, 11)
    return string.format("%x", v)
  end)
end

return M
