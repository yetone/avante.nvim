-- Technical discovery and feasibility assessment module
local storage = require("test_b.storage")

local M = {}

-- Valid impact levels
local VALID_IMPACTS = {
  high = true,
  medium = true,
  low = true
}

-- Get technical data
local function get_technical_data()
  return storage.read("technical") or {
    infrastructure = {},
    integrations = {},
    constraints = {}
  }
end

-- Save technical data
local function save_technical_data(data)
  return storage.write("technical", data)
end

-- Document infrastructure component
function M.document_infrastructure(component)
  if not component.name or component.name == "" then
    return nil, "Component name is required"
  end

  if not component.type or component.type == "" then
    return nil, "Component type is required"
  end

  local data = get_technical_data()

  local infra = {
    id = storage.uuid(),
    name = component.name,
    type = component.type,
    version = component.version or "",
    description = component.description or "",
    created_at = storage.timestamp()
  }

  table.insert(data.infrastructure, infra)

  local ok, err = save_technical_data(data)
  if not ok then
    return nil, err
  end

  return infra
end

-- Add integration point
function M.add_integration_point(integration)
  if not integration.source or integration.source == "" then
    return nil, "Integration source is required"
  end

  if not integration.target or integration.target == "" then
    return nil, "Integration target is required"
  end

  if not integration.protocol or integration.protocol == "" then
    return nil, "Integration protocol is required"
  end

  local data = get_technical_data()

  local integ = {
    id = storage.uuid(),
    source = integration.source,
    target = integration.target,
    protocol = integration.protocol,
    data_flow = integration.data_flow or "bidirectional",
    description = integration.description or "",
    created_at = storage.timestamp()
  }

  table.insert(data.integrations, integ)

  local ok, err = save_technical_data(data)
  if not ok then
    return nil, err
  end

  return integ
end

-- Add technical constraint
function M.add_constraint(constraint)
  if not constraint.type or constraint.type == "" then
    return nil, "Constraint type is required"
  end

  if not constraint.description or constraint.description == "" then
    return nil, "Constraint description is required"
  end

  if not constraint.impact or not VALID_IMPACTS[constraint.impact] then
    return nil, "Invalid or missing impact level"
  end

  local data = get_technical_data()

  local cons = {
    id = storage.uuid(),
    type = constraint.type,
    description = constraint.description,
    impact = constraint.impact,
    mitigation = constraint.mitigation or "",
    created_at = storage.timestamp()
  }

  table.insert(data.constraints, cons)

  local ok, err = save_technical_data(data)
  if not ok then
    return nil, err
  end

  return cons
end

-- Assess requirement feasibility
function M.assess_requirement_feasibility(requirement_id)
  local requirement = require("test_b.requirement").get_requirement(requirement_id)
  if not requirement then
    return nil, "Requirement not found"
  end

  local data = get_technical_data()

  -- Simple feasibility assessment based on constraints
  local high_impact_constraints = 0
  for _, constraint in ipairs(data.constraints) do
    if constraint.impact == "high" then
      high_impact_constraints = high_impact_constraints + 1
    end
  end

  local feasibility_score = 100 - (high_impact_constraints * 10)
  feasibility_score = math.max(0, math.min(100, feasibility_score))

  local assessment = {
    requirement_id = requirement_id,
    feasibility_score = feasibility_score,
    feasibility_level = feasibility_score >= 70 and "high" or
                       (feasibility_score >= 40 and "medium" or "low"),
    constraints_count = #data.constraints,
    high_impact_constraints = high_impact_constraints,
    infrastructure_dependencies = #data.infrastructure,
    integration_points = #data.integrations,
    assessed_at = storage.timestamp()
  }

  return assessment
end

-- Generate feasibility report
function M.generate_feasibility_report()
  local start_time = vim.loop.hrtime()

  local data = get_technical_data()
  local requirements = require("test_b.requirement").list_all()

  local assessments = {}
  for _, req in ipairs(requirements) do
    local assessment = M.assess_requirement_feasibility(req.id)
    table.insert(assessments, assessment)
  end

  -- Calculate overall feasibility
  local total_score = 0
  for _, assessment in ipairs(assessments) do
    total_score = total_score + assessment.feasibility_score
  end
  local avg_score = #assessments > 0 and (total_score / #assessments) or 0

  local report = {
    summary = {
      total_requirements = #requirements,
      average_feasibility_score = avg_score,
      infrastructure_components = #data.infrastructure,
      integration_points = #data.integrations,
      constraints = #data.constraints
    },
    assessments = assessments,
    infrastructure = data.infrastructure,
    integrations = data.integrations,
    constraints = data.constraints,
    generated_at = storage.timestamp()
  }

  local elapsed = (vim.loop.hrtime() - start_time) / 1000000 -- Convert to ms

  return {
    report = report,
    elapsed_ms = elapsed
  }
end

-- Get all technical data
function M.get_all()
  return get_technical_data()
end

return M
