local utils = require("avante.utils")
local PPath = require("plenary.path")

local llm = require("avante.llm")

describe("generate_prompts", function()
  local project_root = "/tmp/project_root"

  before_each(function()
    local mock_dir = PPath:new("tests", project_root)
    mock_dir:mkdir({ parents = true })

    local mock_file = PPath:new("tests", project_root, "avante.md")
    mock_file:write("# Mock Instructions\nThis is a mock instruction file.", "w")

    -- Mock the project root
    utils.root = {}
    utils.root.get = function() return mock_dir end

    -- Mock Config.providers
    local Config = require("avante.config")
    Config.instructions_file = "avante.md"
    Config.provider = "openai"
    Config.providers = {
      openai = {
        endpoint = "https://api.mock.com/v1",
        model = "gpt-mock",
        timeout = 10000,
        context_window = 1000,
        extra_request_body = {
          temperature = 0.5,
          max_tokens = 1000,
        },
      },
    }
    -- Mock Config.history to prevent nil access error in Path.setup()
    Config.history = {
      max_tokens = 4096,
      carried_entry_count = nil,
      storage_path = "/tmp/test_avante_history",
      paste = {
        extension = "png",
        filename = "pasted-%Y-%m-%d-%H-%M-%S",
      },
    }

    -- Mock Config.behaviour
    Config.behaviour = {
      auto_focus_sidebar = true,
      auto_suggestions = false, -- Experimental stage
      auto_suggestions_respect_ignore = false,
      auto_set_highlight_group = true,
      auto_set_keymaps = true,
      auto_apply_diff_after_generation = false,
      jump_result_buffer_on_finish = false,
      support_paste_from_clipboard = false,
      minimize_diff = true,
      enable_token_counting = true,
      use_cwd_as_project_root = false,
      auto_focus_on_diff_view = false,
      auto_approve_tool_permissions = false, -- Default: show permission prompts for all tools
      auto_check_diagnostics = true,
      enable_fastapply = false,
    }

    -- Mock Config.rules to prevent nil access error in get_templates_dir()
    Config.rules = {
      project_dir = nil,
      global_dir = nil,
    }

    -- Mock P.available to always return true
    local Path = require("avante.path")
    Path.available = function() return true end

    -- Mock the Prompt functions directly since _templates_lib is a local variable
    -- that we can't easily access from outside the module
    Path.prompts.initialize = function(cache_directory, project_directory)
      -- Mock initialization - no-op for tests
    end

    Path.prompts.render_file = function(path, opts)
      -- Mock render - return empty string for tests
      return ""
    end

    Path.prompts.render_mode = function(mode, opts)
      -- Mock render_mode - return empty string for tests
      return ""
    end

    Path.setup() -- Initialize necessary paths like cache_path
  end)

  after_each(function()
    -- Clean up created test files and directories
    local mock_dir = PPath:new("tests", project_root)
    if mock_dir:exists() then mock_dir:rmdir() end
  end)

  it("should include instruction file content when the file exists", function()
    local opts = {}
    llm.generate_prompts(opts)
    assert.are.same("\n# Mock Instructions\nThis is a mock instruction file.", opts.instructions)
  end)

  it("should not modify instructions if the file does not exist", function()
    local mock_file = PPath:new("tests", project_root, "avante.md")
    if mock_file:exists() then mock_file:rm() end

    local opts = {}
    llm.generate_prompts(opts)
    assert.are.same(opts.instructions, nil)
  end)
end)
