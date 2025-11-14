-- Technical Discovery Module
-- Manages infrastructure documentation, integration points, and feasibility assessment

local storage = require("test_b.storage")
local uuid = require("test_b.uuid")
local M = {}

-- In-memory storage
local state = {
  technical = {
    infrastructure = {},
    integrations = {},
    constraints = {},
  },
  loaded = false,
}

-- Valid impact levels
local VALID_IMPACTS = {
  high = true,
  medium = true,
  low = true,
}

-- Load technical data from storage
local function load()
  if state.loaded then
    return
  end

  local data, err = storage.read("technical.json")
  if data then
    state.technical = data
  else
    state.technical = {
      infrastructure = {},
      integrations = {},
      constraints = {},
    }
  end
  state.loaded = true
end

-- Save technical data to storage
local function save()
  return storage.write("technical.json", state.technical)
end

-- Document infrastructure component
-- @param component table {name, type, version, [description]}
-- @return table|nil Component object or nil on error
-- @return string|nil Error message if failed
function M.document_infrastructure(component)
  load()

  -- Validate required fields
  if not component.name or component.name == "" then
    return nil, "Component name is required"
  end
  if not component.type or component.type == "" then
    return nil, "Component type is required"
  end

  -- Create infrastructure component
  local infra = {
    id = uuid.generate(),
    name = component.name,
    type = component.type,
    version = component.version or "",
    description = component.description or "",
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Add to infrastructure list
  table.insert(state.technical.infrastructure, infra)

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save infrastructure: " .. tostring(err)
  end

  return infra, nil
end

-- Add integration point
-- @param integration table {source, target, protocol, [data_flow]}
-- @return table|nil Integration object or nil on error
-- @return string|nil Error message if failed
function M.add_integration_point(integration)
  load()

  -- Validate required fields
  if not integration.source or integration.source == "" then
    return nil, "Integration source is required"
  end
  if not integration.target or integration.target == "" then
    return nil, "Integration target is required"
  end
  if not integration.protocol or integration.protocol == "" then
    return nil, "Integration protocol is required"
  end

  -- Create integration object
  local integ = {
    id = uuid.generate(),
    source = integration.source,
    target = integration.target,
    protocol = integration.protocol,
    data_flow = integration.data_flow or "bidirectional",
    description = integration.description or "",
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Add to integrations list
  table.insert(state.technical.integrations, integ)

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save integration: " .. tostring(err)
  end

  return integ, nil
end

-- Add technical constraint
-- @param constraint table {type, description, impact, [mitigation]}
-- @return table|nil Constraint object or nil on error
-- @return string|nil Error message if failed
function M.add_constraint(constraint)
  load()

  -- Validate required fields
  if not constraint.type or constraint.type == "" then
    return nil, "Constraint type is required"
  end
  if not constraint.description or constraint.description == "" then
    return nil, "Constraint description is required"
  end
  if not constraint.impact or not VALID_IMPACTS[constraint.impact] then
    return nil, "Invalid impact. Must be one of: high, medium, low"
  end

  -- Create constraint object
  local constr = {
    id = uuid.generate(),
    type = constraint.type,
    description = constraint.description,
    impact = constraint.impact,
    mitigation = constraint.mitigation or "",
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Add to constraints list
  table.insert(state.technical.constraints, constr)

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save constraint: " .. tostring(err)
  end

  return constr, nil
end

-- Assess requirement feasibility based on constraints
-- @param req_id string Requirement ID
-- @return table|nil Assessment {feasibility_score, feasibility_level, constraints_count} or nil on error
-- @return string|nil Error message if failed
function M.assess_requirement_feasibility(req_id)
  load()

  -- Get requirement module to check if requirement exists
  local requirement = require("test_b.requirement")
  local req = requirement.get_requirement(req_id)
  if not req then
    return nil, "Requirement not found: " .. req_id
  end

  -- Calculate feasibility score based on constraints
  -- Start with base score of 100
  local score = 100
  local high_constraints = 0
  local medium_constraints = 0
  local low_constraints = 0

  for _, constraint in ipairs(state.technical.constraints) do
    if constraint.impact == "high" then
      high_constraints = high_constraints + 1
      score = score - 10
    elseif constraint.impact == "medium" then
      medium_constraints = medium_constraints + 1
      score = score - 5
    elseif constraint.impact == "low" then
      low_constraints = low_constraints + 1
      score = score - 2
    end
  end

  -- Ensure score doesn't go below 0
  score = math.max(0, score)

  -- Determine feasibility level
  local level
  if score >= 80 then
    level = "high"
  elseif score >= 50 then
    level = "medium"
  else
    level = "low"
  end

  return {
    requirement_id = req_id,
    feasibility_score = score,
    feasibility_level = level,
    constraints_count = high_constraints + medium_constraints + low_constraints,
    high_constraints = high_constraints,
    medium_constraints = medium_constraints,
    low_constraints = low_constraints,
  }, nil
end

-- Generate comprehensive feasibility report
-- @return table|nil Report object or nil on error
-- @return string|nil Error message if failed
function M.generate_feasibility_report()
  load()
  local start_time = vim.loop.hrtime()

  -- Get all requirements
  local requirement = require("test_b.requirement")
  local all_requirements = requirement.get_all_requirements()

  -- Assess feasibility for each requirement
  local assessments = {}
  for _, req in ipairs(all_requirements) do
    local assessment, err = M.assess_requirement_feasibility(req.id)
    if assessment then
      table.insert(assessments, assessment)
    end
  end

  -- Create report
  local report = {
    summary = {
      total_requirements = #all_requirements,
      total_infrastructure = #state.technical.infrastructure,
      total_integrations = #state.technical.integrations,
      total_constraints = #state.technical.constraints,
    },
    assessments = assessments,
    infrastructure = state.technical.infrastructure,
    integrations = state.technical.integrations,
    constraints = state.technical.constraints,
    generated_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  local end_time = vim.loop.hrtime()
  report.elapsed_ms = (end_time - start_time) / 1000000

  return report, nil
end

-- Get all technical data
-- @return table Technical data structure
function M.get_all_technical_data()
  load()
  return state.technical
end

return M
