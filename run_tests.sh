#!/bin/bash

# Test runner for test-b project
# Runs tests using Lua interpreter with Neovim compatibility shims

echo "Installing luarocks dependencies if needed..."
which luarocks > /dev/null 2>&1 && luarocks install dkjson --local || echo "Note: luarocks not available, using fallback JSON"

echo ""
echo "Running test suite..."
echo ""

# Run tests with lua
if command -v nvim &> /dev/null; then
    # Use Neovim if available for better compatibility
    nvim --headless -c "lua package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'; require('tests.test_all_scenarios')" -c "quit"
elif command -v lua &> /dev/null; then
    # Fallback to regular lua
    lua -e "package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'" tests/test_all_scenarios.lua
else
    echo "Error: Neither nvim nor lua found. Please install Lua or Neovim to run tests."
    exit 1
fi

exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
    echo "✓ All tests passed!"
else
    echo "✗ Some tests failed. See output above for details."
fi

exit $exit_code
