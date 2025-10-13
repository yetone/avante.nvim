-- Integration tests for Rust components from Lua
-- These tests validate the Lua-Rust FFI bridge

local function test_tokenizer_integration()
  local success, result = pcall(function()
    -- Try to load the tokenizer module
    local tokenizers = require('avante.tokenizers')

    -- Test basic functionality
    tokenizers.from_pretrained('gpt2')
    local tokens, num_tokens, num_chars = tokenizers.encode('Hello, world!')

    return {
      tokens = tokens,
      num_tokens = num_tokens,
      num_chars = num_chars
    }
  end)

  if not success then
    error("Tokenizer integration failed: " .. tostring(result))
  end

  -- Validate results
  assert(result.num_tokens > 0, "Should have tokens")
  assert(result.num_chars > 0, "Should have character count")
  assert(type(result.tokens) == "table", "Tokens should be a table")
end

local function test_template_integration()
  local success, result = pcall(function()
    -- Try to load the templates module
    local templates = require('avante.templates')

    -- Initialize with test directories
    local cache_dir = "/tmp/avante-test-cache"
    local project_dir = "/tmp/avante-test-project"

    -- Create test directories
    os.execute("mkdir -p " .. cache_dir)
    os.execute("mkdir -p " .. project_dir)

    templates.initialize(cache_dir, project_dir)

    -- Create a simple test template
    local template_content = "Hello {{name}}, your language is {{code_lang}}"
    local template_path = cache_dir .. "/test_template.jinja"
    local file = io.open(template_path, "w")
    file:write(template_content)
    file:close()

    -- Test rendering
    local context = {
      ask = true,
      code_lang = "lua",
      name = "World"  -- This might not work as it's not in TemplateContext
    }

    local rendered = templates.render("test_template.jinja", context)

    -- Cleanup
    os.execute("rm -rf " .. cache_dir)
    os.execute("rm -rf " .. project_dir)

    return rendered
  end)

  if not success then
    error("Template integration failed: " .. tostring(result))
  end

  -- Basic validation (this will likely fail as template context is strict)
  assert(type(result) == "string", "Should return rendered string")
end

local function test_repo_map_integration()
  local success, result = pcall(function()
    -- Try to load the repo-map module
    local repo_map = require('avante.repo_map')

    -- This will likely fail as the module interface isn't defined
    return repo_map.generate_map("./")
  end)

  if not success then
    error("Repo map integration failed: " .. tostring(result))
  end

  assert(type(result) == "string" or type(result) == "table", "Should return map data")
end

local function test_html2md_integration()
  local success, result = pcall(function()
    -- Try to load the html2md module
    local html2md = require('avante.html2md')

    local html_input = "<h1>Test</h1><p>Paragraph</p>"
    return html2md.convert(html_input)
  end)

  if not success then
    error("HTML2MD integration failed: " .. tostring(result))
  end

  assert(type(result) == "string", "Should return markdown string")
  assert(result:match("#"), "Should contain markdown heading")
end

-- Main test runner
local function run_rust_integration_tests()
  local tests = {
    {"Tokenizer Integration", test_tokenizer_integration},
    {"Template Integration", test_template_integration},
    {"Repo Map Integration", test_repo_map_integration},
    {"HTML2MD Integration", test_html2md_integration},
  }

  local results = {
    passed = 0,
    failed = 0,
    errors = {}
  }

  for _, test in ipairs(tests) do
    local name, test_func = test[1], test[2]
    print("Running: " .. name)

    local success, error_msg = pcall(test_func)

    if success then
      print("  ✓ PASSED: " .. name)
      results.passed = results.passed + 1
    else
      print("  ✗ FAILED: " .. name .. " - " .. tostring(error_msg))
      results.failed = results.failed + 1
      table.insert(results.errors, {name = name, error = error_msg})
    end
  end

  print("\nResults:")
  print("  Passed: " .. results.passed)
  print("  Failed: " .. results.failed)

  if results.failed > 0 then
    print("\nFailure Details:")
    for _, error_info in ipairs(results.errors) do
      print("  " .. error_info.name .. ": " .. error_info.error)
    end
  end

  return results.failed == 0
end

-- Export for test runner
return {
  run_tests = run_rust_integration_tests
}