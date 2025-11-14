-- Stakeholder Module
-- Manages stakeholder identification, tracking, and engagement

local storage = require("test_b.storage")
local uuid = require("test_b.uuid")
local M = {}

-- In-memory storage
local state = {
  stakeholders = {
    list = {},
    by_id = {},
  },
  loaded = false,
}

-- Valid roles
local VALID_ROLES = {
  business_owner = true,
  end_user = true,
  technical = true,
  reviewer = true,
}

-- Load stakeholders from storage
local function load()
  if state.loaded then
    return
  end

  local data, err = storage.read("stakeholders.json")
  if data then
    state.stakeholders = data
  else
    -- Initialize empty structure
    state.stakeholders = { list = {}, by_id = {} }
  end
  state.loaded = true
end

-- Save stakeholders to storage
local function save()
  return storage.write("stakeholders.json", state.stakeholders)
end

-- Create a new stakeholder
-- @param data table {name, role, email, [contact_info], [responsibilities]}
-- @return table|nil Stakeholder object or nil on error
-- @return string|nil Error message if failed
function M.create_stakeholder(data)
  load()

  -- Validate required fields
  if not data.name or data.name == "" then
    return nil, "Stakeholder name is required"
  end
  if not data.role or data.role == "" then
    return nil, "Stakeholder role is required"
  end
  if not VALID_ROLES[data.role] then
    return nil, "Invalid role. Must be one of: business_owner, end_user, technical, reviewer"
  end
  if not data.email or data.email == "" then
    return nil, "Stakeholder email is required"
  end

  -- Check for duplicate email
  for _, stakeholder in ipairs(state.stakeholders.list) do
    if stakeholder.email == data.email then
      return nil, "Stakeholder with email '" .. data.email .. "' already exists"
    end
  end

  -- Create stakeholder object
  local stakeholder = {
    id = uuid.generate(),
    name = data.name,
    role = data.role,
    email = data.email,
    contact_info = data.contact_info or {},
    responsibilities = data.responsibilities or "",
    engagement_events = {},
    approval_status = "pending",
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Store in both list and by_id
  table.insert(state.stakeholders.list, stakeholder)
  state.stakeholders.by_id[stakeholder.id] = stakeholder

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save stakeholder: " .. tostring(err)
  end

  return stakeholder, nil
end

-- List stakeholders by role
-- @param role string Role to filter by
-- @return table|nil Array of stakeholders or nil on error
-- @return string|nil Error message if failed
function M.list_stakeholders_by_role(role)
  load()

  if not VALID_ROLES[role] then
    return nil, "Invalid role. Must be one of: business_owner, end_user, technical, reviewer"
  end

  local filtered = {}
  for _, stakeholder in ipairs(state.stakeholders.list) do
    if stakeholder.role == role then
      table.insert(filtered, stakeholder)
    end
  end

  return filtered, nil
end

-- Get stakeholder by ID
-- @param id string Stakeholder ID
-- @return table|nil Stakeholder object or nil if not found
function M.get_stakeholder(id)
  load()
  return state.stakeholders.by_id[id]
end

-- Track engagement event for stakeholder
-- @param stakeholder_id string Stakeholder ID
-- @param event_type string Type of engagement (e.g., 'interview_completed', 'meeting')
-- @param event_date string Date of event
-- @return table|nil Event object or nil on error
-- @return string|nil Error message if failed
function M.track_engagement(stakeholder_id, event_type, event_date)
  load()

  local stakeholder = state.stakeholders.by_id[stakeholder_id]
  if not stakeholder then
    return nil, "Stakeholder not found: " .. stakeholder_id
  end

  -- Create engagement event
  local event = {
    type = event_type,
    date = event_date,
    recorded_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Add to stakeholder's engagement events
  table.insert(stakeholder.engagement_events, event)

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save engagement: " .. tostring(err)
  end

  return event, nil
end

-- Get approval status for all stakeholders
-- @return table Array of {id, name, role, approval_status}
function M.get_stakeholder_approval_status()
  load()

  local statuses = {}
  for _, stakeholder in ipairs(state.stakeholders.list) do
    table.insert(statuses, {
      id = stakeholder.id,
      name = stakeholder.name,
      role = stakeholder.role,
      approval_status = stakeholder.approval_status,
    })
  end

  return statuses
end

-- Update stakeholder approval status
-- @param stakeholder_id string Stakeholder ID
-- @param status string New approval status ('pending', 'approved', 'rejected')
-- @return boolean Success status
-- @return string|nil Error message if failed
function M.update_approval_status(stakeholder_id, status)
  load()

  local stakeholder = state.stakeholders.by_id[stakeholder_id]
  if not stakeholder then
    return false, "Stakeholder not found: " .. stakeholder_id
  end

  stakeholder.approval_status = status
  stakeholder.approval_updated_at = os.date("%Y-%m-%dT%H:%M:%S")

  -- Persist to storage
  return save()
end

-- Get all stakeholders
-- @return table Array of all stakeholders
function M.get_all_stakeholders()
  load()
  return state.stakeholders.list
end

return M
