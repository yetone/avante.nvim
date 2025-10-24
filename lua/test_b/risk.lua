-- Risk assessment and mitigation planning module
local storage = require("test_b.storage")

local M = {}

-- Valid impact levels
local VALID_IMPACTS = {
  high = 3,
  medium = 2,
  low = 1
}

-- Valid probability levels
local VALID_PROBABILITIES = {
  current = 4,
  high = 3,
  medium = 2,
  low = 1
}

-- Valid risk statuses
local VALID_STATUSES = {
  identified = true,
  in_mitigation = true,
  mitigated = true,
  accepted = true
}

-- Get all risks
local function get_all_risks()
  return storage.read("risks") or { list = {}, by_id = {} }
end

-- Save risks
local function save_risks(risks)
  return storage.write("risks", risks)
end

-- Calculate risk severity
function M.calculate_risk_severity(params)
  if not params.impact or not VALID_IMPACTS[params.impact] then
    return nil, "Invalid impact level"
  end

  if not params.probability or not VALID_PROBABILITIES[params.probability] then
    return nil, "Invalid probability level"
  end

  local impact_score = VALID_IMPACTS[params.impact]
  local probability_score = VALID_PROBABILITIES[params.probability]

  local severity_score = impact_score * probability_score

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
    probability_score = probability_score
  }
end

-- Create a risk
function M.create_risk(data)
  if not data.name or data.name == "" then
    return nil, "Risk name is required"
  end

  if not data.impact or not VALID_IMPACTS[data.impact] then
    return nil, "Invalid or missing impact level"
  end

  if not data.probability or not VALID_PROBABILITIES[data.probability] then
    return nil, "Invalid or missing probability level"
  end

  local risks = get_all_risks()

  local severity = M.calculate_risk_severity({
    impact = data.impact,
    probability = data.probability
  })

  local risk = {
    id = storage.uuid(),
    name = data.name,
    description = data.description or "",
    impact = data.impact,
    probability = data.probability,
    severity_score = severity.severity_score,
    priority_level = severity.priority_level,
    status = "identified",
    mitigation_strategies = {},
    status_history = {
      {
        status = "identified",
        timestamp = storage.timestamp()
      }
    },
    created_at = storage.timestamp()
  }

  table.insert(risks.list, risk)
  risks.by_id[risk.id] = risk

  local ok, err = save_risks(risks)
  if not ok then
    return nil, err
  end

  return risk
end

-- Add mitigation strategy to a risk
function M.add_mitigation_strategy(risk_id, strategy)
  if not strategy.action or strategy.action == "" then
    return nil, "Mitigation action is required"
  end

  if not strategy.owner or strategy.owner == "" then
    return nil, "Strategy owner is required"
  end

  if not strategy.deadline or strategy.deadline == "" then
    return nil, "Strategy deadline is required"
  end

  local risks = get_all_risks()
  local risk = risks.by_id[risk_id]

  if not risk then
    return nil, "Risk not found"
  end

  local mitigation = {
    id = storage.uuid(),
    action = strategy.action,
    owner = strategy.owner,
    deadline = strategy.deadline,
    status = strategy.status or "planned",
    created_at = storage.timestamp()
  }

  table.insert(risk.mitigation_strategies, mitigation)

  -- Update risk status to in_mitigation if not already
  if risk.status == "identified" then
    risk.status = "in_mitigation"
    table.insert(risk.status_history, {
      status = "in_mitigation",
      timestamp = storage.timestamp()
    })
  end

  local ok, err = save_risks(risks)
  if not ok then
    return nil, err
  end

  return mitigation
end

-- Get high priority risks
function M.get_high_priority_risks()
  local risks = get_all_risks()
  local high_priority = {}

  for _, risk in ipairs(risks.list) do
    if risk.priority_level == "high" or risk.priority_level == "critical" then
      table.insert(high_priority, risk)
    end
  end

  -- Sort by severity score descending
  table.sort(high_priority, function(a, b)
    return a.severity_score > b.severity_score
  end)

  return high_priority
end

-- Update risk status
function M.update_risk_status(risk_id, status)
  if not VALID_STATUSES[status] then
    return nil, "Invalid status"
  end

  local risks = get_all_risks()
  local risk = risks.by_id[risk_id]

  if not risk then
    return nil, "Risk not found"
  end

  risk.status = status
  table.insert(risk.status_history, {
    status = status,
    timestamp = storage.timestamp()
  })

  local ok, err = save_risks(risks)
  if not ok then
    return nil, err
  end

  return risk
end

-- Get risk by ID
function M.get_risk(risk_id)
  local risks = get_all_risks()
  return risks.by_id[risk_id]
end

-- Get all risks
function M.list_all()
  local risks = get_all_risks()
  return risks.list
end

return M
