---@mod avante-names avante instance name generation
---@brief [[
--- Generates human-readable, memorable names for Avante chat instances.
--- Each name is an adjective + noun combination chosen at random.
---@brief ]]

local M = {}

-- Word lists for generating friendly instance names.
local adjectives = {
  "amber", "azure", "bold", "bright", "calm", "cedar", "cobalt", "cool",
  "crisp", "cyan", "dark", "deep", "dim", "dusk", "fern", "firm", "flame",
  "free", "frost", "gold", "jade", "keen", "light", "lime", "mist", "mint",
  "moon", "moss", "navy", "noir", "oak", "pale", "pine", "pure", "quick",
  "rose", "ruby", "sage", "salt", "sand", "silk", "slim", "snow", "soft",
  "solar", "steel", "storm", "swift", "teal", "warm", "wild", "wise",
}

local nouns = {
  "arc", "ash", "bay", "beam", "bell", "brook", "crest", "crow", "dawn",
  "dune", "elm", "fern", "field", "finch", "fjord", "flame", "flare", "fox",
  "gale", "glen", "grove", "hawk", "hill", "jade", "kite", "lake", "lark",
  "leaf", "lynx", "marsh", "moon", "oak", "owl", "peak", "pine", "pond",
  "raven", "reef", "ridge", "rift", "river", "rock", "seal", "sky", "spark",
  "stone", "stream", "tide", "vale", "wave", "wren",
}

--- Registry of all names currently in use to avoid collisions.
---@type table<string, boolean>
local used_names = {}

--- Generate a unique adjective-noun instance name.
--- If a collision occurs the noun is suffixed with a counter (e.g. "swift-fox-2").
---@return string
function M.generate()
  math.randomseed(os.time() + math.random(1000))
  local max_attempts = 20
  for _ = 1, max_attempts do
    local adj = adjectives[math.random(#adjectives)]
    local noun = nouns[math.random(#nouns)]
    local name = adj .. "-" .. noun
    if not used_names[name] then
      used_names[name] = true
      return name
    end
  end
  -- Fallback: append a random number to guarantee uniqueness.
  local adj = adjectives[math.random(#adjectives)]
  local noun = nouns[math.random(#nouns)]
  local counter = 2
  local candidate = adj .. "-" .. noun .. "-" .. counter
  while used_names[candidate] do
    counter = counter + 1
    candidate = adj .. "-" .. noun .. "-" .. counter
  end
  used_names[candidate] = true
  return candidate
end

--- Mark a name as in use (for names loaded from persisted history).
---@param name string
function M.register(name)
  if name and name ~= "" then used_names[name] = true end
end

--- Release a name so it may be reused.
---@param name string
function M.release(name)
  if name and name ~= "" then used_names[name] = nil end
end

return M

