-- PRD Completion Workflow module
local storage = require("test_b.storage")

local M = {}

-- PRD checklist items from template
local CHECKLIST_ITEMS = {
  "Clear problem statement and business context",
  "Detailed functional requirements (REQ-1 through REQ-n)",
  "Specific non-functional requirements with measurable criteria",
  "User stories with acceptance criteria (if user-facing)",
  "Success metrics and measurement plan",
  "Technical considerations and constraints",
  "Business impact analysis",
  "Resource and timeline estimates",
  "Risk assessment with specific mitigation strategies"
}

-- PRD sections
local PRD_SECTIONS = {
  "executive_summary",
  "problem_statement",
  "functional_requirements",
  "nonfunctional_requirements",
  "success_metrics",
  "technical_considerations",
  "risk_assessment"
}

-- Get workflow data
local function get_workflow_data()
  return storage.read("prd_workflow") or {
    checklist = {},
    sections = {},
    approvals = {}
  }
end

-- Save workflow data
local function save_workflow_data(data)
  return storage.write("prd_workflow", data)
end

-- Initialize PRD checklist
function M.initialize_prd_checklist()
  local start_time = vim.loop.hrtime()

  local data = get_workflow_data()

  data.checklist = {}
  for i, item in ipairs(CHECKLIST_ITEMS) do
    table.insert(data.checklist, {
      id = i,
      description = item,
      completed = false,
      completed_at = nil
    })
  end

  data.sections = {}
  for _, section in ipairs(PRD_SECTIONS) do
    data.sections[section] = {
      status = "pending",
      completed_at = nil
    }
  end

  data.initialized_at = storage.timestamp()

  local ok, err = save_workflow_data(data)
  if not ok then
    return nil, err
  end

  local elapsed = (vim.loop.hrtime() - start_time) / 1000000 -- Convert to ms

  return {
    checklist = data.checklist,
    elapsed_ms = elapsed
  }
end

-- Update section completion status
function M.update_section_status(section_name, status)
  local valid_statuses = { pending = true, in_progress = true, completed = true }

  if not valid_statuses[status] then
    return nil, "Invalid status"
  end

  local data = get_workflow_data()

  if not data.sections[section_name] then
    return nil, "Section not found"
  end

  data.sections[section_name].status = status
  if status == "completed" then
    data.sections[section_name].completed_at = storage.timestamp()
  end

  local ok, err = save_workflow_data(data)
  if not ok then
    return nil, err
  end

  return data.sections[section_name]
end

-- Validate PRD completeness
function M.validate_prd_completeness()
  local start_time = vim.loop.hrtime()

  local data = get_workflow_data()
  local requirements = require("test_b.requirement").list_all()
  local risks = require("test_b.risk").list_all()

  local incomplete_sections = {}

  -- Check if sections are completed
  for section_name, section_data in pairs(data.sections) do
    if section_data.status ~= "completed" then
      table.insert(incomplete_sections, section_name)
    end
  end

  -- Check if there are any requirements
  local has_functional_reqs = false
  local has_nonfunctional_reqs = false

  for _, req in ipairs(requirements) do
    if req.type == "functional" then
      has_functional_reqs = true
    elseif req.type == "nonfunctional" then
      has_nonfunctional_reqs = true
    end
  end

  if not has_functional_reqs then
    table.insert(incomplete_sections, "No functional requirements defined")
  end

  if not has_nonfunctional_reqs then
    table.insert(incomplete_sections, "No non-functional requirements defined")
  end

  -- Check if there are any risks
  if #risks == 0 then
    table.insert(incomplete_sections, "No risks identified")
  end

  local elapsed = (vim.loop.hrtime() - start_time) / 1000000 -- Convert to ms

  return {
    valid = #incomplete_sections == 0,
    incomplete_sections = incomplete_sections,
    elapsed_ms = elapsed
  }
end

-- Submit PRD for approval
function M.submit_for_approval(stakeholder_ids)
  if not stakeholder_ids or #stakeholder_ids == 0 then
    return nil, "At least one stakeholder is required"
  end

  local data = get_workflow_data()

  -- Validate completeness first
  local validation = M.validate_prd_completeness()
  if not validation.valid then
    return nil, "PRD is not complete. Cannot submit for approval."
  end

  data.approvals = {}
  for _, stakeholder_id in ipairs(stakeholder_ids) do
    data.approvals[stakeholder_id] = {
      status = "pending",
      requested_at = storage.timestamp(),
      responded_at = nil
    }
  end

  data.submitted_at = storage.timestamp()

  local ok, err = save_workflow_data(data)
  if not ok then
    return nil, err
  end

  return {
    stakeholder_ids = stakeholder_ids,
    submitted_at = data.submitted_at
  }
end

-- Get approval status
function M.get_approval_status()
  local data = get_workflow_data()
  local stakeholder_module = require("test_b.stakeholder")

  local status = {}

  for stakeholder_id, approval in pairs(data.approvals) do
    local stakeholder = stakeholder_module.get_stakeholder(stakeholder_id)
    table.insert(status, {
      stakeholder_id = stakeholder_id,
      stakeholder_name = stakeholder and stakeholder.name or "Unknown",
      approval_status = approval.status,
      requested_at = approval.requested_at,
      responded_at = approval.responded_at
    })
  end

  return status
end

-- Check if PRD is approved
function M.is_prd_approved()
  local data = get_workflow_data()

  if not data.approvals or vim.tbl_count(data.approvals) == 0 then
    return false
  end

  for _, approval in pairs(data.approvals) do
    if approval.status ~= "approved" then
      return false
    end
  end

  return true
end

-- Update stakeholder approval
function M.update_stakeholder_approval(stakeholder_id, approved)
  local data = get_workflow_data()

  if not data.approvals[stakeholder_id] then
    return nil, "Stakeholder not in approval workflow"
  end

  data.approvals[stakeholder_id].status = approved and "approved" or "rejected"
  data.approvals[stakeholder_id].responded_at = storage.timestamp()

  local ok, err = save_workflow_data(data)
  if not ok then
    return nil, err
  end

  return data.approvals[stakeholder_id]
end

-- Get workflow data
function M.get_workflow()
  return get_workflow_data()
end

return M
