-- Requirements management module
local storage = require("test_b.storage")

local M = {}

-- Valid requirement types
local VALID_TYPES = {
  functional = true,
  nonfunctional = true
}

-- Valid priorities
local VALID_PRIORITIES = {
  high = true,
  medium = true,
  low = true
}

-- Valid statuses
local VALID_STATUSES = {
  pending = true,
  in_progress = true,
  completed = true,
  approved = true
}

-- Get all requirements
local function get_all_requirements()
  return storage.read("requirements") or { list = {}, by_id = {} }
end

-- Save requirements
local function save_requirements(requirements)
  return storage.write("requirements", requirements)
end

-- Create a functional requirement
function M.create_requirement(data)
  if not data.id or data.id == "" then
    return nil, "Requirement ID is required"
  end

  if not data.type or not VALID_TYPES[data.type] then
    return nil, "Invalid or missing requirement type"
  end

  if not data.priority or not VALID_PRIORITIES[data.priority] then
    return nil, "Invalid or missing priority"
  end

  if not data.description or data.description == "" then
    return nil, "Requirement description is required"
  end

  local requirements = get_all_requirements()

  -- Check for duplicate ID
  if requirements.by_id[data.id] then
    return nil, "Requirement with this ID already exists"
  end

  local requirement = {
    id = data.id,
    type = data.type,
    priority = data.priority,
    description = data.description,
    status = data.status or "pending",
    acceptance_criteria = data.acceptance_criteria or {},
    stakeholders = {},
    created_at = storage.timestamp()
  }

  table.insert(requirements.list, requirement)
  requirements.by_id[requirement.id] = requirement

  local ok, err = save_requirements(requirements)
  if not ok then
    return nil, err
  end

  return requirement
end

-- Create a non-functional requirement
function M.create_nfr(data)
  if not data.id or data.id == "" then
    return nil, "NFR ID is required"
  end

  if not data.category or data.category == "" then
    return nil, "NFR category is required"
  end

  if not data.criteria or data.criteria == "" then
    return nil, "Measurable criteria is required"
  end

  local requirements = get_all_requirements()

  -- Check for duplicate ID
  if requirements.by_id[data.id] then
    return nil, "Requirement with this ID already exists"
  end

  local nfr = {
    id = data.id,
    type = "nonfunctional",
    category = data.category,
    criteria = data.criteria,
    priority = data.priority or "medium",
    status = data.status or "pending",
    stakeholders = {},
    created_at = storage.timestamp()
  }

  table.insert(requirements.list, nfr)
  requirements.by_id[nfr.id] = nfr

  local ok, err = save_requirements(requirements)
  if not ok then
    return nil, err
  end

  return nfr
end

-- Link requirement to stakeholder
function M.link_requirement_to_stakeholder(requirement_id, stakeholder_id)
  local requirements = get_all_requirements()
  local requirement = requirements.by_id[requirement_id]

  if not requirement then
    return nil, "Requirement not found"
  end

  -- Check if already linked
  for _, sid in ipairs(requirement.stakeholders) do
    if sid == stakeholder_id then
      return requirement -- Already linked
    end
  end

  table.insert(requirement.stakeholders, stakeholder_id)

  local ok, err = save_requirements(requirements)
  if not ok then
    return nil, err
  end

  return requirement
end

-- Validate requirement completeness
function M.validate_requirement(requirement_id)
  local requirements = get_all_requirements()
  local requirement = requirements.by_id[requirement_id]

  if not requirement then
    return nil, "Requirement not found"
  end

  local issues = {}

  if not requirement.id or requirement.id == "" then
    table.insert(issues, "Missing requirement ID")
  end

  if not requirement.description or requirement.description == "" then
    table.insert(issues, "Missing description")
  end

  if requirement.type == "functional" then
    if not requirement.acceptance_criteria or #requirement.acceptance_criteria == 0 then
      table.insert(issues, "Missing acceptance criteria")
    end
  elseif requirement.type == "nonfunctional" then
    if not requirement.criteria or requirement.criteria == "" then
      table.insert(issues, "Missing measurable criteria")
    end
  end

  if not requirement.priority then
    table.insert(issues, "Missing priority")
  end

  return {
    valid = #issues == 0,
    issues = issues,
    requirement_id = requirement_id
  }
end

-- Get requirements by status
function M.get_requirements_by_status(status)
  if not VALID_STATUSES[status] then
    return nil, "Invalid status"
  end

  local requirements = get_all_requirements()
  local filtered = {}

  for _, req in ipairs(requirements.list) do
    if req.status == status then
      table.insert(filtered, req)
    end
  end

  return filtered
end

-- Get requirement by ID
function M.get_requirement(requirement_id)
  local requirements = get_all_requirements()
  return requirements.by_id[requirement_id]
end

-- Get all requirements
function M.list_all()
  local requirements = get_all_requirements()
  return requirements.list
end

-- Update requirement status
function M.update_status(requirement_id, status)
  if not VALID_STATUSES[status] then
    return nil, "Invalid status"
  end

  local requirements = get_all_requirements()
  local requirement = requirements.by_id[requirement_id]

  if not requirement then
    return nil, "Requirement not found"
  end

  requirement.status = status
  requirement.status_updated_at = storage.timestamp()

  local ok, err = save_requirements(requirements)
  if not ok then
    return nil, err
  end

  return requirement
end

return M
