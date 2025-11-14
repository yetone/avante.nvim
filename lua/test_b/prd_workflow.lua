-- PRD Workflow Module
-- Manages PRD completion tracking and stakeholder approval workflow

local storage = require("test_b.storage")
local M = {}

-- In-memory storage
local state = {
  workflow = {
    checklist = {},
    sections = {},
    approvals = {},
  },
  loaded = false,
}

-- Checklist items
local CHECKLIST_ITEMS = {
  "Define project scope and objectives",
  "Identify and document stakeholders",
  "Gather functional requirements",
  "Gather non-functional requirements",
  "Conduct technical discovery",
  "Assess risks and create mitigation plans",
  "Define success criteria and metrics",
  "Review with stakeholders",
  "Obtain final approvals",
}

-- PRD sections
local PRD_SECTIONS = {
  "executive_summary",
  "requirements",
  "user_stories",
  "technical_considerations",
  "dependencies",
  "risk_assessment",
  "appendices",
}

-- Valid statuses
local VALID_STATUSES = {
  pending = true,
  in_progress = true,
  completed = true,
}

-- Load workflow data from storage
local function load()
  if state.loaded then
    return
  end

  local data, err = storage.read("prd_workflow.json")
  if data then
    state.workflow = data
  else
    state.workflow = {
      checklist = {},
      sections = {},
      approvals = {},
    }
  end
  state.loaded = true
end

-- Save workflow data to storage
local function save()
  return storage.write("prd_workflow.json", state.workflow)
end

-- Initialize PRD checklist
-- @return table|nil Checklist structure or nil on error
-- @return string|nil Error message if failed
function M.initialize_prd_checklist()
  load()
  local start_time = vim.loop.hrtime()

  -- Create checklist items
  state.workflow.checklist = {}
  for _, item in ipairs(CHECKLIST_ITEMS) do
    table.insert(state.workflow.checklist, {
      item = item,
      status = "pending",
      completed_at = nil,
    })
  end

  -- Create section tracking
  state.workflow.sections = {}
  for _, section in ipairs(PRD_SECTIONS) do
    state.workflow.sections[section] = {
      status = "pending",
      completed_at = nil,
    }
  end

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to save checklist: " .. tostring(err)
  end

  local end_time = vim.loop.hrtime()
  local elapsed_ms = (end_time - start_time) / 1000000

  return {
    checklist = state.workflow.checklist,
    sections = state.workflow.sections,
    elapsed_ms = elapsed_ms,
  }, nil
end

-- Update section status
-- @param section string Section name
-- @param status string New status (pending, in_progress, completed)
-- @return table|nil Updated section or nil on error
-- @return string|nil Error message if failed
function M.update_section_status(section, status)
  load()

  if not state.workflow.sections[section] then
    return nil, "Invalid section: " .. section
  end
  if not VALID_STATUSES[status] then
    return nil, "Invalid status. Must be one of: pending, in_progress, completed"
  end

  state.workflow.sections[section].status = status
  if status == "completed" then
    state.workflow.sections[section].completed_at = os.date("%Y-%m-%dT%H:%M:%S")
  end

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to update section: " .. tostring(err)
  end

  return state.workflow.sections[section], nil
end

-- Validate PRD completeness
-- @return table Validation result {valid, incomplete_sections, missing_requirements, missing_risks, elapsed_ms}
function M.validate_prd_completeness()
  load()
  local start_time = vim.loop.hrtime()

  local incomplete_sections = {}
  local issues = {}

  -- Check section completion
  for section, data in pairs(state.workflow.sections) do
    if data.status ~= "completed" then
      table.insert(incomplete_sections, section)
    end
  end

  -- Check requirements
  local requirement = require("test_b.requirement")
  local functional_count = requirement.count_by_type("functional")
  local nonfunctional_count = requirement.count_by_type("nonfunctional")

  if functional_count == 0 then
    table.insert(issues, "No functional requirements documented")
  end
  if nonfunctional_count == 0 then
    table.insert(issues, "No non-functional requirements documented")
  end

  -- Check risks
  local risk = require("test_b.risk")
  local all_risks = risk.get_all_risks()
  if #all_risks == 0 then
    table.insert(issues, "No risks identified")
  end

  local end_time = vim.loop.hrtime()
  local elapsed_ms = (end_time - start_time) / 1000000

  return {
    valid = #incomplete_sections == 0 and #issues == 0,
    incomplete_sections = incomplete_sections,
    issues = issues,
    elapsed_ms = elapsed_ms,
  }
end

-- Submit PRD for stakeholder approval
-- @param stakeholder_ids table Array of stakeholder IDs
-- @return table|nil Approval structure or nil on error
-- @return string|nil Error message if failed
function M.submit_for_approval(stakeholder_ids)
  load()

  if not stakeholder_ids or #stakeholder_ids == 0 then
    return nil, "At least one stakeholder is required for approval"
  end

  -- Validate completeness
  local validation = M.validate_prd_completeness()
  if not validation.valid then
    return nil, "PRD is not complete. Issues: " .. table.concat(validation.incomplete_sections, ", ")
  end

  -- Create approval requests
  state.workflow.approvals = {}
  for _, stakeholder_id in ipairs(stakeholder_ids) do
    state.workflow.approvals[stakeholder_id] = {
      stakeholder_id = stakeholder_id,
      approval_status = "pending",
      requested_at = os.date("%Y-%m-%dT%H:%M:%S"),
      responded_at = nil,
    }
  end

  state.workflow.submitted_at = os.date("%Y-%m-%dT%H:%M:%S")

  -- Persist to storage
  local success, err = save()
  if not success then
    return nil, "Failed to submit for approval: " .. tostring(err)
  end

  return state.workflow.approvals, nil
end

-- Get approval status
-- @return table Array of approval statuses with stakeholder details
function M.get_approval_status()
  load()

  local stakeholder = require("test_b.stakeholder")
  local statuses = {}

  for stakeholder_id, approval in pairs(state.workflow.approvals) do
    local sh = stakeholder.get_stakeholder(stakeholder_id)
    table.insert(statuses, {
      stakeholder_id = stakeholder_id,
      stakeholder_name = sh and sh.name or "Unknown",
      approval_status = approval.approval_status,
      requested_at = approval.requested_at,
      responded_at = approval.responded_at,
    })
  end

  return statuses
end

-- Check if PRD is fully approved
-- @return boolean True if all stakeholders have approved
function M.is_prd_approved()
  load()

  if not state.workflow.approvals or next(state.workflow.approvals) == nil then
    return false
  end

  for _, approval in pairs(state.workflow.approvals) do
    if approval.approval_status ~= "approved" then
      return false
    end
  end

  return true
end

-- Update stakeholder approval
-- @param stakeholder_id string Stakeholder ID
-- @param status string Approval status ('approved', 'rejected', 'pending')
-- @return boolean Success status
-- @return string|nil Error message if failed
function M.update_stakeholder_approval(stakeholder_id, status)
  load()

  if not state.workflow.approvals[stakeholder_id] then
    return false, "Approval not found for stakeholder: " .. stakeholder_id
  end

  state.workflow.approvals[stakeholder_id].approval_status = status
  state.workflow.approvals[stakeholder_id].responded_at = os.date("%Y-%m-%dT%H:%M:%S")

  -- Persist to storage
  return save()
end

-- Get workflow state
-- @return table Complete workflow state
function M.get_workflow_state()
  load()
  return state.workflow
end

return M
