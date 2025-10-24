-- Stakeholder management module
local storage = require("test_b.storage")

local M = {}

-- Valid stakeholder roles
local VALID_ROLES = {
  business_owner = true,
  end_user = true,
  technical = true,
  reviewer = true
}

-- Get all stakeholders
local function get_all_stakeholders()
  return storage.read("stakeholders") or { list = {}, by_id = {} }
end

-- Save stakeholders
local function save_stakeholders(stakeholders)
  return storage.write("stakeholders", stakeholders)
end

-- Create a new stakeholder
function M.create_stakeholder(data)
  if not data.name or data.name == "" then
    return nil, "Stakeholder name is required"
  end

  if not data.role or not VALID_ROLES[data.role] then
    return nil, "Invalid or missing stakeholder role"
  end

  if not data.email or data.email == "" then
    return nil, "Stakeholder email is required"
  end

  local stakeholders = get_all_stakeholders()

  -- Check for duplicate email
  for _, stakeholder in ipairs(stakeholders.list) do
    if stakeholder.email == data.email then
      return nil, "Stakeholder with this email already exists"
    end
  end

  local stakeholder = {
    id = storage.uuid(),
    name = data.name,
    role = data.role,
    email = data.email,
    responsibilities = data.responsibilities or "",
    created_at = storage.timestamp(),
    engagement_events = {},
    approval_status = "pending"
  }

  table.insert(stakeholders.list, stakeholder)
  stakeholders.by_id[stakeholder.id] = stakeholder

  local ok, err = save_stakeholders(stakeholders)
  if not ok then
    return nil, err
  end

  return stakeholder
end

-- List stakeholders by role
function M.list_stakeholders_by_role(role)
  if not VALID_ROLES[role] then
    return nil, "Invalid role"
  end

  local stakeholders = get_all_stakeholders()
  local filtered = {}

  for _, stakeholder in ipairs(stakeholders.list) do
    if stakeholder.role == role then
      table.insert(filtered, stakeholder)
    end
  end

  return filtered
end

-- Get stakeholder by ID
function M.get_stakeholder(stakeholder_id)
  local stakeholders = get_all_stakeholders()
  return stakeholders.by_id[stakeholder_id]
end

-- Track engagement event
function M.track_engagement(stakeholder_id, event_type, date)
  local stakeholders = get_all_stakeholders()
  local stakeholder = stakeholders.by_id[stakeholder_id]

  if not stakeholder then
    return nil, "Stakeholder not found"
  end

  local event = {
    type = event_type,
    date = date or storage.timestamp(),
    recorded_at = storage.timestamp()
  }

  table.insert(stakeholder.engagement_events, event)

  local ok, err = save_stakeholders(stakeholders)
  if not ok then
    return nil, err
  end

  return event
end

-- Get stakeholder approval status
function M.get_stakeholder_approval_status()
  local stakeholders = get_all_stakeholders()
  local status = {}

  for _, stakeholder in ipairs(stakeholders.list) do
    table.insert(status, {
      id = stakeholder.id,
      name = stakeholder.name,
      role = stakeholder.role,
      approval_status = stakeholder.approval_status
    })
  end

  return status
end

-- Update stakeholder approval status
function M.update_approval_status(stakeholder_id, status)
  local stakeholders = get_all_stakeholders()
  local stakeholder = stakeholders.by_id[stakeholder_id]

  if not stakeholder then
    return nil, "Stakeholder not found"
  end

  stakeholder.approval_status = status
  stakeholder.approval_updated_at = storage.timestamp()

  local ok, err = save_stakeholders(stakeholders)
  if not ok then
    return nil, err
  end

  return stakeholder
end

-- Get all stakeholders
function M.list_all()
  local stakeholders = get_all_stakeholders()
  return stakeholders.list
end

return M
