#!/usr/bin/env -S nvim -l

-- Simple test runner for test-b project
-- Can be run with: nvim -l tests/run_tests.lua

-- Add lua directory to package path
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

-- Load the main module
local ok, test_b = pcall(require, "test_b")
if not ok then
  print("Error loading test_b module: " .. tostring(test_b))
  os.exit(1)
end

-- Initialize
test_b.setup({ storage_path = ".something/test_data" })

-- Clean test data
os.execute("rm -rf .something/test_data && mkdir -p .something/test_data")

print("\n" .. string.rep("=", 70))
print("TEST-B: Requirements Gathering System - Test Suite")
print(string.rep("=", 70))

local passed = 0
local failed = 0
local tests = {}

local function test(name, fn)
  io.write(string.format("\n%-60s ", name))
  io.flush()

  local success, err = pcall(fn)
  if success then
    io.write("✓ PASS\n")
    passed = passed + 1
    table.insert(tests, { name = name, status = "passed" })
  else
    io.write("✗ FAIL\n")
    io.write("  Error: " .. tostring(err) .. "\n")
    failed = failed + 1
    table.insert(tests, { name = name, status = "failed", error = tostring(err) })
  end
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(msg or string.format("Expected '%s' but got '%s'", tostring(expected), tostring(actual)))
  end
end

local function assert_true(value, msg)
  if not value then
    error(msg or "Expected true but got false")
  end
end

local function assert_not_nil(value, msg)
  if value == nil then
    error(msg or "Expected non-nil value")
  end
end

-- Scenario 1: Project Initialization
print("\n--- SCENARIO 1: Project Initialization ---")

test("S1T1: Initialize project with metadata", function()
  local proj = test_b.project.initialize("test-b", "aaa")
  assert_not_nil(proj)
  assert_eq(proj.title, "test-b")
  assert_eq(proj.description, "aaa")
end)

test("S1T2: Read project info from file", function()
  local info = test_b.project.read_project_info()
  assert_not_nil(info)
  assert_eq(info.title, "test-b")
end)

test("S1T3: Generate PRD template", function()
  local result = test_b.project.generate_prd_template()
  assert_not_nil(result)
  assert_not_nil(result.template)
  assert_true(#result.template.sections >= 4)
end)

-- Scenario 2: Stakeholder Management
print("\n--- SCENARIO 2: Stakeholder Management ---")

local stakeholder_id

test("S2T1: Create stakeholder", function()
  local s = test_b.stakeholder.create_stakeholder({
    name = "John Doe",
    role = "business_owner",
    email = "john@example.com"
  })
  assert_not_nil(s)
  assert_eq(s.name, "John Doe")
  stakeholder_id = s.id
end)

test("S2T2: List stakeholders by role", function()
  local list = test_b.stakeholder.list_stakeholders_by_role("business_owner")
  assert_not_nil(list)
  assert_true(#list >= 1)
end)

test("S2T3: Track engagement event", function()
  local event = test_b.stakeholder.track_engagement(stakeholder_id, "interview_completed", "2025-10-24")
  assert_not_nil(event)
  assert_eq(event.type, "interview_completed")
end)

test("S2T4: Get approval status", function()
  local status = test_b.stakeholder.get_stakeholder_approval_status()
  assert_not_nil(status)
  assert_true(#status >= 1)
end)

-- Scenario 3: Requirements Management
print("\n--- SCENARIO 3: Requirements Management ---")

test("S3T1: Create functional requirement", function()
  local req = test_b.requirement.create_requirement({
    id = "REQ-1",
    type = "functional",
    priority = "high",
    description = "User authentication"
  })
  assert_not_nil(req)
  assert_eq(req.id, "REQ-1")
end)

test("S3T2: Create non-functional requirement", function()
  local nfr = test_b.requirement.create_nfr({
    id = "NFR-1",
    category = "performance",
    criteria = "Response time < 200ms"
  })
  assert_not_nil(nfr)
  assert_eq(nfr.id, "NFR-1")
end)

test("S3T3: Link requirement to stakeholder", function()
  local req = test_b.requirement.link_requirement_to_stakeholder("REQ-1", stakeholder_id)
  assert_not_nil(req)
  assert_true(#req.stakeholders >= 1)
end)

test("S3T4: Validate requirement", function()
  local val = test_b.requirement.validate_requirement("REQ-1")
  assert_not_nil(val)
end)

test("S3T5: Get requirements by status", function()
  local reqs = test_b.requirement.get_requirements_by_status("pending")
  assert_not_nil(reqs)
  assert_true(#reqs >= 2)
end)

-- Scenario 4: Technical Discovery
print("\n--- SCENARIO 4: Technical Discovery ---")

test("S4T1: Document infrastructure", function()
  local infra = test_b.technical.document_infrastructure({
    name = "Database",
    type = "PostgreSQL",
    version = "14.5"
  })
  assert_not_nil(infra)
  assert_eq(infra.name, "Database")
end)

test("S4T2: Add integration point", function()
  local integ = test_b.technical.add_integration_point({
    source = "SystemA",
    target = "SystemB",
    protocol = "REST"
  })
  assert_not_nil(integ)
  assert_eq(integ.protocol, "REST")
end)

test("S4T3: Add constraint", function()
  local cons = test_b.technical.add_constraint({
    type = "technical",
    description = "Legacy system compatibility",
    impact = "high"
  })
  assert_not_nil(cons)
  assert_eq(cons.impact, "high")
end)

test("S4T4: Assess requirement feasibility", function()
  local assess = test_b.technical.assess_requirement_feasibility("REQ-1")
  assert_not_nil(assess)
  assert_not_nil(assess.feasibility_score)
end)

test("S4T5: Generate feasibility report", function()
  local result = test_b.technical.generate_feasibility_report()
  assert_not_nil(result)
  assert_not_nil(result.report)
end)

-- Scenario 5: Risk Management
print("\n--- SCENARIO 5: Risk Management ---")

local risk_id

test("S5T1: Create risk", function()
  local risk = test_b.risk.create_risk({
    name = "Insufficient Requirements",
    impact = "high",
    probability = "current"
  })
  assert_not_nil(risk)
  assert_not_nil(risk.severity_score)
  risk_id = risk.id
end)

test("S5T2: Calculate risk severity", function()
  local sev = test_b.risk.calculate_risk_severity({
    impact = "high",
    probability = "high"
  })
  assert_not_nil(sev)
  assert_not_nil(sev.severity_score)
end)

test("S5T3: Add mitigation strategy", function()
  local strat = test_b.risk.add_mitigation_strategy(risk_id, {
    action = "Conduct requirements workshop",
    owner = "PM",
    deadline = "2025-11-01"
  })
  assert_not_nil(strat)
  assert_eq(strat.owner, "PM")
end)

test("S5T4: Get high priority risks", function()
  local risks = test_b.risk.get_high_priority_risks()
  assert_not_nil(risks)
  assert_true(#risks >= 1)
end)

test("S5T5: Update risk status", function()
  local risk = test_b.risk.update_risk_status(risk_id, "mitigated")
  assert_not_nil(risk)
  assert_eq(risk.status, "mitigated")
end)

-- Scenario 6: PRD Workflow
print("\n--- SCENARIO 6: PRD Workflow ---")

test("S6T1: Initialize PRD checklist", function()
  local result = test_b.prd_workflow.initialize_prd_checklist()
  assert_not_nil(result)
  assert_not_nil(result.checklist)
  assert_true(#result.checklist >= 8)
end)

test("S6T2: Update section status", function()
  local sec = test_b.prd_workflow.update_section_status("functional_requirements", "completed")
  assert_not_nil(sec)
  assert_eq(sec.status, "completed")
end)

test("S6T3: Validate PRD completeness", function()
  local val = test_b.prd_workflow.validate_prd_completeness()
  assert_not_nil(val)
end)

-- Complete sections for approval
test_b.prd_workflow.update_section_status("executive_summary", "completed")
test_b.prd_workflow.update_section_status("problem_statement", "completed")
test_b.prd_workflow.update_section_status("nonfunctional_requirements", "completed")
test_b.prd_workflow.update_section_status("success_metrics", "completed")
test_b.prd_workflow.update_section_status("technical_considerations", "completed")
test_b.prd_workflow.update_section_status("risk_assessment", "completed")

test("S6T4: Submit for approval", function()
  local result = test_b.prd_workflow.submit_for_approval({ stakeholder_id })
  assert_not_nil(result)
  assert_not_nil(result.submitted_at)
end)

test("S6T5: Get approval status", function()
  local status = test_b.prd_workflow.get_approval_status()
  assert_not_nil(status)
  assert_true(#status >= 1)
end)

test("S6T6: Check PRD approval", function()
  local is_approved = test_b.prd_workflow.is_prd_approved()
  assert_eq(is_approved, false)

  test_b.prd_workflow.update_stakeholder_approval(stakeholder_id, true)

  is_approved = test_b.prd_workflow.is_prd_approved()
  assert_eq(is_approved, true)
end)

-- Summary
print("\n" .. string.rep("=", 70))
print(string.format("RESULTS: %d passed, %d failed (%.1f%% success rate)",
  passed, failed, (passed / (passed + failed)) * 100))
print(string.rep("=", 70))

-- Write results
local results = {
  passed = passed,
  failed = failed,
  total = passed + failed,
  tests = tests,
  timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
}

local file = io.open(".something/TEST_RESULTS.json", "w")
if file then
  file:write(vim.json.encode(results))
  file:close()
end

os.exit(failed > 0 and 1 or 0)
