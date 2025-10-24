-- Project module for initialization and configuration
local storage = require("test_b.storage")

local M = {}

-- Read project information from project.md
function M.read_project_info()
  local filepath = ".something/reference/project.md"
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Project file not found"
  end

  local content = file:read("*all")
  file:close()

  -- Parse markdown to extract title and description
  local title = content:match("## Title%s*\n([^\n]+)")
  local description = content:match("## Description%s*\n([^\n]+)")

  if not title or not description then
    return nil, "Failed to parse project information"
  end

  return {
    title = title,
    description = description
  }
end

-- Initialize project with metadata
function M.initialize(project_title, project_description)
  if not project_title or project_title == "" then
    return nil, "Project title is required"
  end

  if not project_description or project_description == "" then
    return nil, "Project description is required"
  end

  local project = {
    title = project_title,
    description = project_description,
    created_at = storage.timestamp(),
    status = "initialized"
  }

  local ok, err = storage.write("project", project)
  if not ok then
    return nil, err
  end

  return project
end

-- Validate project configuration
function M.validate()
  local project = storage.read("project")
  if not project then
    return false, "Project not initialized"
  end

  if not project.title or project.title == "" then
    return false, "Missing project title"
  end

  if not project.description or project.description == "" then
    return false, "Missing project description"
  end

  return true
end

-- Get project configuration
function M.get_config()
  return storage.read("project")
end

-- Generate PRD template structure
function M.generate_prd_template()
  local start_time = vim.loop.hrtime()

  local project_info, err = M.read_project_info()
  if not project_info then
    return nil, err
  end

  local template = {
    project_title = project_info.title,
    sections = {
      {
        name = "Executive Summary",
        subsections = {
          "Project Overview",
          "Problem Statement",
          "Proposed Solution",
          "Expected Impact",
          "Success Metrics"
        }
      },
      {
        name = "Requirements & Scope",
        subsections = {
          "Functional Requirements",
          "Non-Functional Requirements",
          "Out of Scope",
          "Success Criteria"
        }
      },
      {
        name = "Dependencies & Assumptions",
        subsections = {
          "Current Status",
          "Required Next Steps",
          "Assumptions",
          "Dependencies"
        }
      },
      {
        name = "Risk Assessment",
        subsections = {
          "Current Risks"
        }
      },
      {
        name = "Next Steps",
        subsections = {
          "Immediate Actions",
          "PRD Completion Checklist"
        }
      }
    },
    generated_at = storage.timestamp()
  }

  local ok, err = storage.write("prd_template", template)
  if not ok then
    return nil, err
  end

  local elapsed = (vim.loop.hrtime() - start_time) / 1000000 -- Convert to ms

  return {
    template = template,
    elapsed_ms = elapsed
  }
end

return M
