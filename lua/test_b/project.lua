-- Project Module
-- Manages project initialization and PRD template generation

local storage = require("test_b.storage")
local M = {}

-- Read project information from .something/reference/project.md
-- @return table|nil {title, description} or nil on error
-- @return string|nil Error message if failed
function M.read_project_info()
  local project_file = ".something/reference/project.md"

  local file = io.open(project_file, "r")
  if not file then
    return nil, "Project file not found: " .. project_file
  end

  local content = file:read("*all")
  file:close()

  -- Parse markdown to extract title and description
  local title = content:match("## Title%s*\n([^\n]+)")
  local description = content:match("## Description%s*\n([^\n]+)")

  if not title or not description then
    return nil, "Failed to parse project.md - missing title or description"
  end

  return { title = title, description = description }, nil
end

-- Initialize a new project with metadata
-- @param title string Project title
-- @param description string Project description
-- @return table|nil Project object or nil on error
-- @return string|nil Error message if failed
function M.initialize(title, description)
  -- Validate inputs
  if not title or title == "" then
    return nil, "Project title is required"
  end
  if not description or description == "" then
    return nil, "Project description is required"
  end

  -- Create project metadata
  local project = {
    title = title,
    description = description,
    status = "initialized",
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
    updated_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  -- Store project metadata
  local success, err = storage.write("project.json", project)
  if not success then
    return nil, "Failed to store project: " .. tostring(err)
  end

  return project, nil
end

-- Get project metadata
-- @return table|nil Project object or nil on error
-- @return string|nil Error message if failed
function M.get_project()
  local project, err = storage.read("project.json")
  if not project then
    return nil, err
  end
  return project, nil
end

-- Update project metadata
-- @param updates table Fields to update
-- @return table|nil Updated project or nil on error
-- @return string|nil Error message if failed
function M.update_project(updates)
  local project, err = M.get_project()
  if not project then
    return nil, err
  end

  -- Apply updates
  for k, v in pairs(updates) do
    project[k] = v
  end
  project.updated_at = os.date("%Y-%m-%dT%H:%M:%S")

  -- Store updated project
  local success, store_err = storage.write("project.json", project)
  if not success then
    return nil, "Failed to update project: " .. tostring(store_err)
  end

  return project, nil
end

-- Generate PRD template with all required sections
-- @return table|nil PRD structure or nil on error
-- @return string|nil Error message if failed
function M.generate_prd_template()
  local start_time = vim.loop.hrtime()

  local prd = {
    title = "Product Requirements Document",
    sections = {
      {
        name = "executive_summary",
        title = "Executive Summary",
        content = "",
        subsections = {
          { name = "problem_statement", title = "Problem Statement", content = "" },
          { name = "proposed_solution", title = "Proposed Solution", content = "" },
          { name = "expected_impact", title = "Expected Impact", content = "" },
          { name = "success_metrics", title = "Success Metrics", content = "" },
        },
      },
      {
        name = "requirements",
        title = "Requirements & Scope",
        content = "",
        subsections = {
          { name = "functional_requirements", title = "Functional Requirements", content = "" },
          { name = "nonfunctional_requirements", title = "Non-Functional Requirements", content = "" },
          { name = "out_of_scope", title = "Out of Scope", content = "" },
          { name = "success_criteria", title = "Success Criteria", content = "" },
        },
      },
      {
        name = "user_stories",
        title = "User Stories",
        content = "",
        subsections = {
          { name = "personas", title = "Personas", content = "" },
          { name = "core_stories", title = "Core User Stories", content = "" },
        },
      },
      {
        name = "technical_considerations",
        title = "Technical Considerations",
        content = "",
        subsections = {
          { name = "architecture", title = "High-Level Technical Approach", content = "" },
          { name = "integrations", title = "Integration Points", content = "" },
          { name = "constraints", title = "Technical Constraints", content = "" },
          { name = "performance", title = "Performance Considerations", content = "" },
        },
      },
      {
        name = "dependencies",
        title = "Dependencies & Assumptions",
        content = "",
        subsections = {
          { name = "external_dependencies", title = "External Dependencies", content = "" },
          { name = "assumptions", title = "Assumptions", content = "" },
          { name = "coordination", title = "Cross-Team Coordination", content = "" },
        },
      },
    },
    created_at = os.date("%Y-%m-%dT%H:%M:%S"),
  }

  local end_time = vim.loop.hrtime()
  local elapsed_ms = (end_time - start_time) / 1000000

  prd.elapsed_ms = elapsed_ms

  return prd, nil
end

return M
