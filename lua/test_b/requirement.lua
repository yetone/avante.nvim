-- Requirement Module
-- Manages functional and non-functional requirements

local storage = require("test_b.storage")
local M = {}

-- In-memory storage
local state = {
  requirements = {
    list = {},
    by_id = {},
  },
  loaded = false,
}

-- Valid constants
local VALID_TYPES = {
  functional = true,
  nonfunctional = true,
  constraint = true,
}

local VALID_PRIORITIES = {
  high = true,
  medium = true,
  low = true,
}

local VALID_STATUSES = {
  pending = true,
  in_progress = true,
  completed = true,
  approved = true,
}

-- Load requirements from storage
local function load()
  if state.loaded then
    return
  end

  local data, err = storage.read("requirements.json")
  if data then
    state.requirements = data
  else
    state.requirements = { list = {}, by_id = {} }
  end
  state.loaded = true
end

-- Save requirements to storage
local function save()
  return storage.write("requirements.json", state.requirements)
end

-- Create a functional requirement
-- @param data table {id, type, priority, description, [acceptance_criteria]}
-- @return table|nil Requirement object or nil on error
-- @return string|nil Error message if failed
function M.create_requirement(data)
  load()

  -- Validate required fields
  if not data.id or data.id == "" then
    return nil, "Requirement ID is required"
  end
  if state.requirements.by_id[data.id] then
    return nil, "Requirement with ID '" .. data.id .. "' already exists"
  end
  if not data.type or not VALID_TYPES[data.type] then
    return nil, "Invalid type. Must be one of: functional, nonfunctional, constraint"
  end
  if not data.priority or not VALID_PRIORITIES[data.priority] then
    return nil, "Invalid priority. Must be one of: high, medium, low"
  end
  if not data.description or data.description == "" then
    return nil, "Requirement description is required"
  end

  -- Create requirement object
  local requirement = {
    id = data.id,
    type = data.type,
    priority = data.priority,
    description = data.description,
    acceptance_criteria = data.acceptance_criteria or {},
    stakeholders = {},
    status = "pending",
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Store in both list and by_id
  table.insert(state.requirements.list, requirement)
  state.requirements.by_id[requirement.id] = requirement

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save requirement: " .. tostring(err)
  end

  return requirement, nil
end

-- Create a non-functional requirement
-- @param data table {id, category, criteria, [description]}
-- @return table|nil NFR object or nil on error
-- @return string|nil Error message if failed
function M.create_nfr(data)
  load()

  -- Validate required fields
  if not data.id or data.id == "" then
    return nil, "NFR ID is required"
  end
  if state.requirements.by_id[data.id] then
    return nil, "Requirement with ID '" .. data.id .. "' already exists"
  end
  if not data.category or data.category == "" then
    return nil, "NFR category is required"
  end
  if not data.criteria or data.criteria == "" then
    return nil, "NFR criteria is required"
  end

  -- Create NFR object
  local nfr = {
    id = data.id,
    type = "nonfunctional",
    category = data.category,
    criteria = data.criteria,
    description = data.description or "",
    stakeholders = {},
    status = "pending",
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Store in both list and by_id
  table.insert(state.requirements.list, nfr)
  state.requirements.by_id[nfr.id] = nfr

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save NFR: " .. tostring(err)
  end

  return nfr, nil
end

-- Link requirement to stakeholder
-- @param req_id string Requirement ID
-- @param stakeholder_id string Stakeholder ID
-- @return table|nil Updated requirement or nil on error
-- @return string|nil Error message if failed
function M.link_requirement_to_stakeholder(req_id, stakeholder_id)
  load()

  local requirement = state.requirements.by_id[req_id]
  if not requirement then
    return nil, "Requirement not found: " .. req_id
  end

  -- Check if already linked
  for _, id in ipairs(requirement.stakeholders) do
    if id == stakeholder_id then
      return nil, "Stakeholder already linked to requirement"
    end
  end

  -- Add stakeholder link
  table.insert(requirement.stakeholders, stakeholder_id)

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save requirement link: " .. tostring(err)
  end

  return requirement, nil
end

-- Validate requirement completeness
-- @param req_id string Requirement ID
-- @return table Validation result {valid, issues}
function M.validate_requirement(req_id)
  load()

  local requirement = state.requirements.by_id[req_id]
  if not requirement then
    return { valid = false, issues = { "Requirement not found" } }
  end

  local issues = {}

  -- Check required fields
  if not requirement.description or requirement.description == "" then
    table.insert(issues, "Missing description")
  end

  -- Type-specific validation
  if requirement.type == "functional" then
    if
      not requirement.acceptance_criteria
      or (type(requirement.acceptance_criteria) == "table" and #requirement.acceptance_criteria == 0)
    then
      table.insert(issues, "Missing acceptance criteria")
    end
  elseif requirement.type == "nonfunctional" then
    if not requirement.criteria or requirement.criteria == "" then
      table.insert(issues, "Missing measurable criteria")
    end
  end

  -- Check stakeholder linkage
  if #requirement.stakeholders == 0 then
    table.insert(issues, "No stakeholders linked")
  end

  return {
    valid = #issues == 0,
    issues = issues,
  }
end

-- Get requirements by status
-- @param status string Status to filter by
-- @return table|nil Array of requirements or nil on error
-- @return string|nil Error message if failed
function M.get_requirements_by_status(status)
  load()

  if not VALID_STATUSES[status] then
    return nil, "Invalid status. Must be one of: pending, in_progress, completed, approved"
  end

  local filtered = {}
  for _, requirement in ipairs(state.requirements.list) do
    if requirement.status == status then
      table.insert(filtered, requirement)
    end
  end

  return filtered, nil
end

-- Get requirement by ID
-- @param id string Requirement ID
-- @return table|nil Requirement object or nil if not found
function M.get_requirement(id)
  load()
  return state.requirements.by_id[id]
end

-- Get all requirements
-- @return table Array of all requirements
function M.get_all_requirements()
  load()
  return state.requirements.list
end

-- Count requirements by type
-- @param req_type string Requirement type
-- @return number Count of requirements
function M.count_by_type(req_type)
  load()
  local count = 0
  for _, req in ipairs(state.requirements.list) do
    if req.type == req_type then
      count = count + 1
    end
  end
  return count
end

return M
