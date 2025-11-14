-- Test suite for test_b modules
-- Tests all scenarios from scenarios.json

local test_b = require("test_b")

describe("test_b Requirements Gathering System", function()
  -- Clean up storage before each test
  before_each(function()
    local data_dir = test_b.storage.get_data_dir()
    vim.fn.delete(data_dir, "rf")
    vim.fn.mkdir(data_dir, "p")
  end)

  describe("Scenario 1: Requirements Gathering Initialization", function()
    it("should initialize project with minimal information", function()
      local project, err = test_b.project.initialize("test-b", "aaa")

      assert.is_nil(err)
      assert.is_not_nil(project)
      assert.equals("test-b", project.title)
      assert.equals("aaa", project.description)
      assert.equals("initialized", project.status)
      assert.is_not_nil(project.created_at)
    end)

    it("should read project info from project.md", function()
      local info, err = test_b.project.read_project_info()

      assert.is_nil(err)
      assert.is_not_nil(info)
      assert.equals("test-b", info.title)
      assert.equals("aaa", info.description)
    end)

    it("should generate PRD template with required sections", function()
      local prd, err = test_b.project.generate_prd_template()

      assert.is_nil(err)
      assert.is_not_nil(prd)
      assert.is_true(#prd.sections >= 4)
      assert.is_not_nil(prd.elapsed_ms)
      assert.is_true(prd.elapsed_ms < 500)
    end)
  end)

  describe("Scenario 2: Stakeholder Identification and Management", function()
    it("should create stakeholder with all required fields", function()
      local stakeholder, err = test_b.stakeholder.create_stakeholder({
        name = "John Doe",
        role = "business_owner",
        email = "john@example.com",
      })

      assert.is_nil(err)
      assert.is_not_nil(stakeholder)
      assert.is_not_nil(stakeholder.id)
      assert.equals("John Doe", stakeholder.name)
      assert.equals("business_owner", stakeholder.role)
      assert.equals("john@example.com", stakeholder.email)
    end)

    it("should list stakeholders by role", function()
      test_b.stakeholder.create_stakeholder({
        name = "John Doe",
        role = "business_owner",
        email = "john@example.com",
      })

      test_b.stakeholder.create_stakeholder({
        name = "Jane Smith",
        role = "business_owner",
        email = "jane@example.com",
      })

      local stakeholders, err = test_b.stakeholder.list_stakeholders_by_role("business_owner")

      assert.is_nil(err)
      assert.equals(2, #stakeholders)
      assert.equals("business_owner", stakeholders[1].role)
    end)

    it("should track engagement events", function()
      local stakeholder, _ = test_b.stakeholder.create_stakeholder({
        name = "John Doe",
        role = "business_owner",
        email = "john@example.com",
      })

      local event, err = test_b.stakeholder.track_engagement(stakeholder.id, "interview_completed", "2025-10-24")

      assert.is_nil(err)
      assert.is_not_nil(event)
      assert.equals("interview_completed", event.type)
      assert.equals("2025-10-24", event.date)
      assert.is_not_nil(event.recorded_at)
    end)

    it("should get stakeholder approval status", function()
      test_b.stakeholder.create_stakeholder({
        name = "John Doe",
        role = "business_owner",
        email = "john@example.com",
      })

      local statuses = test_b.stakeholder.get_stakeholder_approval_status()

      assert.equals(1, #statuses)
      assert.equals("John Doe", statuses[1].name)
      assert.equals("business_owner", statuses[1].role)
      assert.is_not_nil(statuses[1].approval_status)
    end)
  end)

  describe("Scenario 3: Requirements Documentation and Validation", function()
    it("should create functional requirement", function()
      local req, err = test_b.requirement.create_requirement({
        id = "REQ-1",
        type = "functional",
        priority = "high",
        description = "User authentication",
      })

      assert.is_nil(err)
      assert.is_not_nil(req)
      assert.equals("REQ-1", req.id)
      assert.equals("functional", req.type)
      assert.equals("high", req.priority)
    end)

    it("should create non-functional requirement", function()
      local nfr, err = test_b.requirement.create_nfr({
        id = "NFR-1",
        category = "performance",
        criteria = "Response time < 200ms",
      })

      assert.is_nil(err)
      assert.is_not_nil(nfr)
      assert.equals("NFR-1", nfr.id)
      assert.equals("performance", nfr.category)
      assert.equals("nonfunctional", nfr.type)
    end)

    it("should link requirement to stakeholder", function()
      local req, _ = test_b.requirement.create_requirement({
        id = "REQ-1",
        type = "functional",
        priority = "high",
        description = "User authentication",
      })

      local stakeholder, _ = test_b.stakeholder.create_stakeholder({
        name = "John Doe",
        role = "business_owner",
        email = "john@example.com",
      })

      local updated_req, err = test_b.requirement.link_requirement_to_stakeholder(req.id, stakeholder.id)

      assert.is_nil(err)
      assert.is_not_nil(updated_req)
      assert.equals(1, #updated_req.stakeholders)
    end)

    it("should validate requirement completeness", function()
      test_b.requirement.create_requirement({
        id = "REQ-1",
        type = "functional",
        priority = "high",
        description = "User authentication",
      })

      local validation = test_b.requirement.validate_requirement("REQ-1")

      assert.is_not_nil(validation)
      assert.is_not_nil(validation.valid)
      assert.is_not_nil(validation.issues)
    end)

    it("should get requirements by status", function()
      test_b.requirement.create_requirement({
        id = "REQ-1",
        type = "functional",
        priority = "high",
        description = "User authentication",
      })

      local reqs, err = test_b.requirement.get_requirements_by_status("pending")

      assert.is_nil(err)
      assert.equals(1, #reqs)
      assert.equals("pending", reqs[1].status)
    end)
  end)

  describe("Scenario 4: Technical Discovery and Feasibility Assessment", function()
    it("should document infrastructure component", function()
      local infra, err = test_b.technical.document_infrastructure({
        name = "Database",
        type = "PostgreSQL",
        version = "14.5",
      })

      assert.is_nil(err)
      assert.is_not_nil(infra)
      assert.is_not_nil(infra.id)
      assert.equals("Database", infra.name)
      assert.equals("PostgreSQL", infra.type)
      assert.equals("14.5", infra.version)
    end)

    it("should add integration point", function()
      local integration, err = test_b.technical.add_integration_point({
        source = "SystemA",
        target = "SystemB",
        protocol = "REST",
      })

      assert.is_nil(err)
      assert.is_not_nil(integration)
      assert.equals("SystemA", integration.source)
      assert.equals("SystemB", integration.target)
      assert.equals("REST", integration.protocol)
      assert.equals("bidirectional", integration.data_flow)
    end)

    it("should add technical constraint", function()
      local constraint, err = test_b.technical.add_constraint({
        type = "technical",
        description = "Legacy system compatibility",
        impact = "high",
      })

      assert.is_nil(err)
      assert.is_not_nil(constraint)
      assert.equals("technical", constraint.type)
      assert.equals("high", constraint.impact)
    end)

    it("should assess requirement feasibility", function()
      test_b.requirement.create_requirement({
        id = "REQ-1",
        type = "functional",
        priority = "high",
        description = "User authentication",
      })

      local assessment, err = test_b.technical.assess_requirement_feasibility("REQ-1")

      assert.is_nil(err)
      assert.is_not_nil(assessment)
      assert.is_not_nil(assessment.feasibility_score)
      assert.is_not_nil(assessment.feasibility_level)
      assert.is_not_nil(assessment.constraints_count)
    end)

    it("should generate feasibility report", function()
      test_b.requirement.create_requirement({
        id = "REQ-1",
        type = "functional",
        priority = "high",
        description = "User authentication",
      })

      local report, err = test_b.technical.generate_feasibility_report()

      assert.is_nil(err)
      assert.is_not_nil(report)
      assert.is_not_nil(report.summary)
      assert.is_not_nil(report.assessments)
      assert.is_not_nil(report.elapsed_ms)
      assert.is_true(report.elapsed_ms < 2000)
    end)
  end)

  describe("Scenario 5: Risk Assessment and Mitigation Planning", function()
    it("should create risk with severity calculation", function()
      local risk, err = test_b.risk.create_risk({
        name = "Insufficient Requirements",
        impact = "high",
        probability = "current",
      })

      assert.is_nil(err)
      assert.is_not_nil(risk)
      assert.is_not_nil(risk.id)
      assert.is_not_nil(risk.severity_score)
      assert.is_not_nil(risk.priority_level)
      assert.equals("identified", risk.status)
    end)

    it("should calculate risk severity correctly", function()
      local severity, err = test_b.risk.calculate_risk_severity({
        impact = "high",
        probability = "high",
      })

      assert.is_nil(err)
      assert.is_not_nil(severity)
      assert.equals(9, severity.severity_score)
      assert.equals("critical", severity.priority_level)
      assert.equals(3, severity.impact_score)
      assert.equals(3, severity.probability_score)
    end)

    it("should add mitigation strategy", function()
      local risk, _ = test_b.risk.create_risk({
        name = "Insufficient Requirements",
        impact = "high",
        probability = "current",
      })

      local strategy, err = test_b.risk.add_mitigation_strategy(risk.id, {
        action = "Conduct workshop",
        owner = "PM",
        deadline = "2025-11-01",
      })

      assert.is_nil(err)
      assert.is_not_nil(strategy)
      assert.is_not_nil(strategy.id)
      assert.equals("Conduct workshop", strategy.action)
      assert.equals("PM", strategy.owner)
      assert.equals("planned", strategy.status)

      -- Verify risk status updated
      local updated_risk = test_b.risk.get_risk(risk.id)
      assert.equals("in_mitigation", updated_risk.status)
    end)

    it("should get high priority risks", function()
      test_b.risk.create_risk({
        name = "Risk 1",
        impact = "high",
        probability = "high",
      })

      test_b.risk.create_risk({
        name = "Risk 2",
        impact = "low",
        probability = "rare",
      })

      local high_risks = test_b.risk.get_high_priority_risks()

      assert.equals(1, #high_risks)
      assert.is_true(high_risks[1].priority_level == "high" or high_risks[1].priority_level == "critical")
    end)

    it("should update risk status with history", function()
      local risk, _ = test_b.risk.create_risk({
        name = "Risk 1",
        impact = "high",
        probability = "high",
      })

      local updated_risk, err = test_b.risk.update_risk_status(risk.id, "mitigated")

      assert.is_nil(err)
      assert.is_not_nil(updated_risk)
      assert.equals("mitigated", updated_risk.status)
      assert.equals(2, #updated_risk.status_history)
    end)
  end)

  describe("Scenario 6: PRD Completion Workflow", function()
    it("should initialize PRD checklist", function()
      local result, err = test_b.prd_workflow.initialize_prd_checklist()

      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.equals(9, #result.checklist)
      assert.is_not_nil(result.sections)
      assert.is_not_nil(result.elapsed_ms)
      assert.is_true(result.elapsed_ms < 100)
    end)

    it("should update section status", function()
      test_b.prd_workflow.initialize_prd_checklist()

      local section, err = test_b.prd_workflow.update_section_status("requirements", "completed")

      assert.is_nil(err)
      assert.is_not_nil(section)
      assert.equals("completed", section.status)
      assert.is_not_nil(section.completed_at)
    end)

    it("should validate PRD completeness", function()
      test_b.prd_workflow.initialize_prd_checklist()

      local validation = test_b.prd_workflow.validate_prd_completeness()

      assert.is_not_nil(validation)
      assert.is_not_nil(validation.valid)
      assert.is_not_nil(validation.incomplete_sections)
      assert.is_not_nil(validation.elapsed_ms)
      assert.is_true(validation.elapsed_ms < 500)
    end)

    it("should submit for approval", function()
      test_b.prd_workflow.initialize_prd_checklist()

      -- Complete all sections
      local sections = { "executive_summary", "requirements", "user_stories", "technical_considerations", "dependencies", "risk_assessment", "appendices" }
      for _, section in ipairs(sections) do
        test_b.prd_workflow.update_section_status(section, "completed")
      end

      -- Create requirements and risks
      test_b.requirement.create_requirement({
        id = "REQ-1",
        type = "functional",
        priority = "high",
        description = "Test requirement",
      })

      test_b.requirement.create_nfr({
        id = "NFR-1",
        category = "performance",
        criteria = "Response time < 200ms",
      })

      test_b.risk.create_risk({
        name = "Test risk",
        impact = "low",
        probability = "rare",
      })

      -- Create stakeholder
      local stakeholder, _ = test_b.stakeholder.create_stakeholder({
        name = "John Doe",
        role = "business_owner",
        email = "john@example.com",
      })

      local approvals, err = test_b.prd_workflow.submit_for_approval({ stakeholder.id })

      assert.is_nil(err)
      assert.is_not_nil(approvals)
    end)

    it("should get approval status", function()
      test_b.prd_workflow.initialize_prd_checklist()

      -- Complete all sections
      local sections = { "executive_summary", "requirements", "user_stories", "technical_considerations", "dependencies", "risk_assessment", "appendices" }
      for _, section in ipairs(sections) do
        test_b.prd_workflow.update_section_status(section, "completed")
      end

      -- Create requirements and risks
      test_b.requirement.create_requirement({
        id = "REQ-1",
        type = "functional",
        priority = "high",
        description = "Test requirement",
      })

      test_b.requirement.create_nfr({
        id = "NFR-1",
        category = "performance",
        criteria = "Response time < 200ms",
      })

      test_b.risk.create_risk({
        name = "Test risk",
        impact = "low",
        probability = "rare",
      })

      local stakeholder, _ = test_b.stakeholder.create_stakeholder({
        name = "John Doe",
        role = "business_owner",
        email = "john@example.com",
      })

      test_b.prd_workflow.submit_for_approval({ stakeholder.id })

      local statuses = test_b.prd_workflow.get_approval_status()

      assert.equals(1, #statuses)
      assert.equals("John Doe", statuses[1].stakeholder_name)
      assert.is_not_nil(statuses[1].approval_status)
    end)

    it("should check if PRD is approved", function()
      test_b.prd_workflow.initialize_prd_checklist()

      local is_approved = test_b.prd_workflow.is_prd_approved()
      assert.is_false(is_approved)

      -- After all stakeholders approve, it should return true
      -- (This would require setting up full approval workflow)
    end)
  end)
end)
