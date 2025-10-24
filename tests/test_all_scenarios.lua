-- Comprehensive test suite for all scenarios
-- This file tests all 6 scenarios from SCENARIOS_TO_BUILD.json

local test_b = require("test_b")

-- Mock vim global if not available
if not vim then
  _G.vim = {
    loop = {
      hrtime = function()
        return os.clock() * 1000000000
      end
    },
    json = {
      encode = function(data)
        -- Simple JSON encode for testing
        return require("dkjson").encode(data)
      end,
      decode = function(str)
        -- Simple JSON decode for testing
        return require("dkjson").decode(str)
      end
    },
    fn = {
      mkdir = function(path, flags)
        os.execute("mkdir -p " .. path)
      end
    },
    tbl_count = function(t)
      local count = 0
      for _ in pairs(t) do
        count = count + 1
      end
      return count
    end
  }
end

-- Test results tracking
local test_results = {
  passed = 0,
  failed = 0,
  tests = {}
}

-- Helper functions
local function assert_equal(actual, expected, message)
  if actual == expected then
    return true
  else
    error(message or string.format("Expected %s but got %s", tostring(expected), tostring(actual)))
  end
end

local function assert_not_nil(value, message)
  if value ~= nil then
    return true
  else
    error(message or "Expected non-nil value")
  end
end

local function assert_nil(value, message)
  if value == nil then
    return true
  else
    error(message or "Expected nil value")
  end
end

local function run_test(name, func)
  print(string.format("\n=== Running: %s ===", name))
  local success, err = pcall(func)

  if success then
    print("✓ PASSED")
    test_results.passed = test_results.passed + 1
    table.insert(test_results.tests, {
      name = name,
      status = "passed"
    })
  else
    print("✗ FAILED: " .. tostring(err))
    test_results.failed = test_results.failed + 1
    table.insert(test_results.tests, {
      name = name,
      status = "failed",
      error = tostring(err)
    })
  end
end

-- Setup test environment
print("Setting up test environment...")
test_b.setup({ storage_path = ".something/test_data" })

-- Clean up any existing test data
os.execute("rm -rf .something/test_data")
os.execute("mkdir -p .something/test_data")

print("\n" .. string.rep("=", 60))
print("SCENARIO 1: Requirements Gathering Initialization")
print(string.rep("=", 60))

run_test("Scenario 1, Test 1: Initialize project with metadata", function()
  local project = test_b.project.initialize("test-b", "aaa")
  assert_not_nil(project, "Project should be initialized")
  assert_equal(project.title, "test-b")
  assert_equal(project.description, "aaa")
  assert_equal(project.status, "initialized")
end)

run_test("Scenario 1, Test 2: Read project info from file", function()
  local info, err = test_b.project.read_project_info()
  assert_not_nil(info, "Should read project info: " .. tostring(err))
  assert_equal(info.title, "test-b")
  assert_equal(info.description, "aaa")
end)

run_test("Scenario 1, Test 3: Generate PRD template", function()
  local result, err = test_b.project.generate_prd_template()
  assert_not_nil(result, "Should generate PRD template: " .. tostring(err))
  assert_not_nil(result.template)
  assert_not_nil(result.template.sections)
  assert_equal(#result.template.sections >= 4, true, "Should have at least 4 sections")
  assert_equal(result.elapsed_ms < 500, true, "Should complete in under 500ms")
end)

print("\n" .. string.rep("=", 60))
print("SCENARIO 2: Stakeholder Identification and Management")
print(string.rep("=", 60))

run_test("Scenario 2, Test 1: Create stakeholder", function()
  local stakeholder = test_b.stakeholder.create_stakeholder({
    name = "John Doe",
    role = "business_owner",
    email = "john@example.com"
  })
  assert_not_nil(stakeholder)
  assert_equal(stakeholder.name, "John Doe")
  assert_equal(stakeholder.role, "business_owner")
  assert_not_nil(stakeholder.id)
end)

run_test("Scenario 2, Test 2: List stakeholders by role", function()
  local stakeholders = test_b.stakeholder.list_stakeholders_by_role("business_owner")
  assert_not_nil(stakeholders)
  assert_equal(#stakeholders >= 1, true)
  assert_equal(stakeholders[1].role, "business_owner")
end)

local test_stakeholder_id

run_test("Scenario 2, Test 3: Track engagement event", function()
  local stakeholders = test_b.stakeholder.list_all()
  test_stakeholder_id = stakeholders[1].id

  local event = test_b.stakeholder.track_engagement(
    test_stakeholder_id,
    "interview_completed",
    "2025-10-24"
  )
  assert_not_nil(event)
  assert_equal(event.type, "interview_completed")
end)

run_test("Scenario 2, Test 4: Get stakeholder approval status", function()
  local status = test_b.stakeholder.get_stakeholder_approval_status()
  assert_not_nil(status)
  assert_equal(#status >= 1, true)
end)

print("\n" .. string.rep("=", 60))
print("SCENARIO 3: Requirements Documentation and Validation")
print(string.rep("=", 60))

run_test("Scenario 3, Test 1: Create functional requirement", function()
  local req = test_b.requirement.create_requirement({
    id = "REQ-1",
    type = "functional",
    priority = "high",
    description = "User authentication"
  })
  assert_not_nil(req)
  assert_equal(req.id, "REQ-1")
  assert_equal(req.type, "functional")
  assert_equal(req.priority, "high")
end)

run_test("Scenario 3, Test 2: Create non-functional requirement", function()
  local nfr = test_b.requirement.create_nfr({
    id = "NFR-1",
    category = "performance",
    criteria = "Response time < 200ms"
  })
  assert_not_nil(nfr)
  assert_equal(nfr.id, "NFR-1")
  assert_equal(nfr.category, "performance")
end)

run_test("Scenario 3, Test 3: Link requirement to stakeholder", function()
  local req = test_b.requirement.link_requirement_to_stakeholder("REQ-1", test_stakeholder_id)
  assert_not_nil(req)
  assert_equal(#req.stakeholders >= 1, true)
end)

run_test("Scenario 3, Test 4: Validate requirement", function()
  local validation = test_b.requirement.validate_requirement("REQ-1")
  assert_not_nil(validation)
  assert_not_nil(validation.valid)
end)

run_test("Scenario 3, Test 5: Get requirements by status", function()
  local reqs = test_b.requirement.get_requirements_by_status("pending")
  assert_not_nil(reqs)
  -- Should have at least REQ-1 and NFR-1
  assert_equal(#reqs >= 2, true)
end)

print("\n" .. string.rep("=", 60))
print("SCENARIO 4: Technical Discovery and Feasibility Assessment")
print(string.rep("=", 60))

run_test("Scenario 4, Test 1: Document infrastructure", function()
  local infra = test_b.technical.document_infrastructure({
    name = "Database",
    type = "PostgreSQL",
    version = "14.5"
  })
  assert_not_nil(infra)
  assert_equal(infra.name, "Database")
  assert_equal(infra.type, "PostgreSQL")
end)

run_test("Scenario 4, Test 2: Add integration point", function()
  local integ = test_b.technical.add_integration_point({
    source = "SystemA",
    target = "SystemB",
    protocol = "REST"
  })
  assert_not_nil(integ)
  assert_equal(integ.source, "SystemA")
  assert_equal(integ.protocol, "REST")
end)

run_test("Scenario 4, Test 3: Add constraint", function()
  local constraint = test_b.technical.add_constraint({
    type = "technical",
    description = "Legacy system compatibility",
    impact = "high"
  })
  assert_not_nil(constraint)
  assert_equal(constraint.impact, "high")
end)

run_test("Scenario 4, Test 4: Assess requirement feasibility", function()
  local assessment = test_b.technical.assess_requirement_feasibility("REQ-1")
  assert_not_nil(assessment)
  assert_not_nil(assessment.feasibility_score)
  assert_not_nil(assessment.feasibility_level)
end)

run_test("Scenario 4, Test 5: Generate feasibility report", function()
  local result = test_b.technical.generate_feasibility_report()
  assert_not_nil(result)
  assert_not_nil(result.report)
  assert_not_nil(result.report.summary)
  assert_equal(result.elapsed_ms < 2000, true, "Should complete in under 2 seconds")
end)

print("\n" .. string.rep("=", 60))
print("SCENARIO 5: Risk Assessment and Mitigation Planning")
print(string.rep("=", 60))

local test_risk_id

run_test("Scenario 5, Test 1: Create risk", function()
  local risk = test_b.risk.create_risk({
    name = "Insufficient Requirements",
    impact = "high",
    probability = "current",
    description = "Limited project description may lead to scope ambiguity"
  })
  assert_not_nil(risk)
  assert_equal(risk.name, "Insufficient Requirements")
  assert_not_nil(risk.severity_score)
  test_risk_id = risk.id
end)

run_test("Scenario 5, Test 2: Calculate risk severity", function()
  local severity = test_b.risk.calculate_risk_severity({
    impact = "high",
    probability = "high"
  })
  assert_not_nil(severity)
  assert_not_nil(severity.severity_score)
  assert_not_nil(severity.priority_level)
end)

run_test("Scenario 5, Test 3: Add mitigation strategy", function()
  local strategy = test_b.risk.add_mitigation_strategy(test_risk_id, {
    action = "Conduct requirements workshop",
    owner = "PM",
    deadline = "2025-11-01"
  })
  assert_not_nil(strategy)
  assert_equal(strategy.action, "Conduct requirements workshop")
  assert_equal(strategy.owner, "PM")
end)

run_test("Scenario 5, Test 4: Get high priority risks", function()
  local risks = test_b.risk.get_high_priority_risks()
  assert_not_nil(risks)
  assert_equal(#risks >= 1, true)
end)

run_test("Scenario 5, Test 5: Update risk status", function()
  local risk = test_b.risk.update_risk_status(test_risk_id, "mitigated")
  assert_not_nil(risk)
  assert_equal(risk.status, "mitigated")
  assert_not_nil(risk.status_history)
  assert_equal(#risk.status_history >= 2, true)
end)

print("\n" .. string.rep("=", 60))
print("SCENARIO 6: PRD Completion Workflow")
print(string.rep("=", 60))

run_test("Scenario 6, Test 1: Initialize PRD checklist", function()
  local result = test_b.prd_workflow.initialize_prd_checklist()
  assert_not_nil(result)
  assert_not_nil(result.checklist)
  assert_equal(#result.checklist >= 8, true)
  assert_equal(result.elapsed_ms < 100, true, "Should complete in under 100ms")
end)

run_test("Scenario 6, Test 2: Update section status", function()
  local section = test_b.prd_workflow.update_section_status("functional_requirements", "completed")
  assert_not_nil(section)
  assert_equal(section.status, "completed")
  assert_not_nil(section.completed_at)
end)

run_test("Scenario 6, Test 3: Validate PRD completeness", function()
  local validation = test_b.prd_workflow.validate_prd_completeness()
  assert_not_nil(validation)
  assert_not_nil(validation.valid)
  assert_equal(validation.elapsed_ms < 500, true, "Should complete in under 500ms")
end)

-- Complete more sections for approval test
test_b.prd_workflow.update_section_status("executive_summary", "completed")
test_b.prd_workflow.update_section_status("problem_statement", "completed")
test_b.prd_workflow.update_section_status("nonfunctional_requirements", "completed")
test_b.prd_workflow.update_section_status("success_metrics", "completed")
test_b.prd_workflow.update_section_status("technical_considerations", "completed")
test_b.prd_workflow.update_section_status("risk_assessment", "completed")

run_test("Scenario 6, Test 4: Submit for approval", function()
  local result = test_b.prd_workflow.submit_for_approval({ test_stakeholder_id })
  assert_not_nil(result)
  assert_not_nil(result.submitted_at)
end)

run_test("Scenario 6, Test 5: Get approval status", function()
  local status = test_b.prd_workflow.get_approval_status()
  assert_not_nil(status)
  assert_equal(#status >= 1, true)
end)

run_test("Scenario 6, Test 6: Check if PRD is approved", function()
  -- Initially should not be approved
  local is_approved = test_b.prd_workflow.is_prd_approved()
  assert_equal(is_approved, false)

  -- Approve it
  test_b.prd_workflow.update_stakeholder_approval(test_stakeholder_id, true)

  -- Now should be approved
  is_approved = test_b.prd_workflow.is_prd_approved()
  assert_equal(is_approved, true)
end)

-- Print final results
print("\n" .. string.rep("=", 60))
print("TEST SUMMARY")
print(string.rep("=", 60))
print(string.format("Total tests: %d", test_results.passed + test_results.failed))
print(string.format("Passed: %d", test_results.passed))
print(string.format("Failed: %d", test_results.failed))
print(string.format("Success rate: %.1f%%", (test_results.passed / (test_results.passed + test_results.failed)) * 100))

-- Write test results to file
local results_json = vim.json.encode(test_results)
local file = io.open(".something/TEST_RESULTS.json", "w")
if file then
  file:write(results_json)
  file:close()
  print("\nTest results written to .something/TEST_RESULTS.json")
end

-- Exit with appropriate code
if test_results.failed > 0 then
  os.exit(1)
else
  os.exit(0)
end
