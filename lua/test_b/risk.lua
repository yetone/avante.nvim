-- Risk Management Module
-- Manages risk assessment, severity calculation, and mitigation strategies

local storage = require("test_b.storage")
local uuid = require("test_b.uuid")
local M = {}

-- In-memory storage
local state = {
  risks = {
    list = {},
    by_id = {},
  },
  loaded = false,
}

-- Valid constants
local VALID_IMPACTS = {
  low = 1,
  medium = 2,
  high = 3,
}

local VALID_PROBABILITIES = {
  rare = 1,
  unlikely = 2,
  likely = 3,
  current = 3, -- Alias for 'likely'
  high = 4,
}

local VALID_STATUSES = {
  identified = true,
  in_mitigation = true,
  mitigated = true,
  accepted = true,
}

-- Load risks from storage
local function load()
  if state.loaded then
    return
  end

  local data, err = storage.read("risks.json")
  if data then
    state.risks = data
  else
    state.risks = { list = {}, by_id = {} }
  end
  state.loaded = true
end

-- Save risks to storage
local function save()
  return storage.write("risks.json", state.risks)
end

-- Calculate risk severity using impact × probability matrix
-- @param params table {impact, probability}
-- @return table|nil Severity result {severity_score, priority_level, impact_score, probability_score} or nil on error
-- @return string|nil Error message if failed
function M.calculate_risk_severity(params)
  if not params.impact or not VALID_IMPACTS[params.impact] then
    return nil, "Invalid impact. Must be one of: low, medium, high"
  end
  if not params.probability or not VALID_PROBABILITIES[params.probability] then
    return nil, "Invalid probability. Must be one of: rare, unlikely, likely, current, high"
  end

  local impact_score = VALID_IMPACTS[params.impact]
  local probability_score = VALID_PROBABILITIES[params.probability]
  local severity_score = impact_score * probability_score

  -- Determine priority level based on severity score
  -- Score range: 1-12 (low*rare=1, high*high=12)
  local priority_level
  if severity_score >= 9 then
    priority_level = "critical"
  elseif severity_score >= 6 then
    priority_level = "high"
  elseif severity_score >= 3 then
    priority_level = "medium"
  else
    priority_level = "low"
  end

  return {
    severity_score = severity_score,
    priority_level = priority_level,
    impact_score = impact_score,
    probability_score = probability_score,
  }, nil
end

-- Create a new risk
-- @param data table {name, impact, probability, [description]}
-- @return table|nil Risk object or nil on error
-- @return string|nil Error message if failed
function M.create_risk(data)
  load()

  -- Validate required fields
  if not data.name or data.name == "" then
    return nil, "Risk name is required"
  end
  if not data.impact or not VALID_IMPACTS[data.impact] then
    return nil, "Invalid impact. Must be one of: low, medium, high"
  end
  if not data.probability or not VALID_PROBABILITIES[data.probability] then
    return nil, "Invalid probability. Must be one of: rare, unlikely, likely, current, high"
  end

  -- Calculate severity
  local severity, err = M.calculate_risk_severity({ impact = data.impact, probability = data.probability })
  if not severity then
    return nil, err
  end

  -- Create risk object
  local risk = {
    id = uuid.generate(),
    name = data.name,
    description = data.description or "",
    impact = data.impact,
    probability = data.probability,
    severity_score = severity.severity_score,
    priority_level = severity.priority_level,
    status = "identified",
    mitigation_strategies = {},
    status_history = {
      { status = "identified", timestamp = os.date("%Y-%m-%dT%H:%M:%S") },
    },
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Store in both list and by_id
  table.insert(state.risks.list, risk)
  state.risks.by_id[risk.id] = risk

  -- Persist to storage
  local success, save_err = save()
  if not success then
    return nil, "Failed to save risk: " .. tostring(save_err)
  end

  return risk, nil
end

-- Add mitigation strategy to a risk
-- @param risk_id string Risk ID
-- @param strategy table {action, owner, deadline, [description]}
-- @return table|nil Strategy object or nil on error
-- @return string|nil Error message if failed
function M.add_mitigation_strategy(risk_id, strategy)
  load()

  local risk = state.risks.by_id[risk_id]
  if not risk then
    return nil, "Risk not found: " .. risk_id
  end

  -- Validate required fields
  if not strategy.action or strategy.action == "" then
    return nil, "Strategy action is required"
  end
  if not strategy.owner or strategy.owner == "" then
    return nil, "Strategy owner is required"
  end
  if not strategy.deadline or strategy.deadline == "" then
    return nil, "Strategy deadline is required"
  end

  -- Create strategy object
  local strat = {
    id = uuid.generate(),
    action = strategy.action,
    owner = strategy.owner,
    deadline = strategy.deadline,
    description = strategy.description or "",
    status = "planned",
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Add to risk's mitigation strategies
  table.insert(risk.mitigation_strategies, strat)

  -- Update risk status to in_mitigation if not already
  if risk.status == "identified" then
    risk.status = "in_mitigation"
    table.insert(risk.status_history, { status = "in_mitigation", timestamp = os.date("%Y-%m-%dT%H:%M:%S") })
  end

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save mitigation strategy: " .. tostring(err)
  end

  return strat, nil
end

-- Get high-priority risks (high and critical)
-- @return table Array of high-priority risks sorted by severity_score
function M.get_high_priority_risks()
  load()

  local high_priority = {}
  for _, risk in ipairs(state.risks.list) do
    if risk.priority_level == "high" or risk.priority_level == "critical" then
      table.insert(high_priority, risk)
    end
  end

  -- Sort by severity_score descending
  table.sort(high_priority, function(a, b)
    return a.severity_score > b.severity_score
  end)

  return high_priority
end

-- Update risk status
-- @param risk_id string Risk ID
-- @param status string New status
-- @return table|nil Updated risk or nil on error
-- @return string|nil Error message if failed
function M.update_risk_status(risk_id, status)
  load()

  if not VALID_STATUSES[status] then
    return nil, "Invalid status. Must be one of: identified, in_mitigation, mitigated, accepted"
  end

  local risk = state.risks.by_id[risk_id]
  if not risk then
    return nil, "Risk not found: " .. risk_id
  end

  -- Update status and add to history
  risk.status = status
  table.insert(risk.status_history, { status = status, timestamp = os.date("%Y-%m-%dT%H:%M:%S") })

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to update risk status: " .. tostring(err)
  end

  return risk, nil
end

-- Get all risks
-- @return table Array of all risks
function M.get_all_risks()
  load()
  return state.risks.list
end

-- Get risk by ID
-- @param id string Risk ID
-- @return table|nil Risk object or nil if not found
function M.get_risk(id)
  load()
  return state.risks.by_id[id]
end

return M
