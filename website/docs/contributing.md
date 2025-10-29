# Contributing

Thank you for your interest in contributing to avante.nvim! This guide will help you get started.

## Ways to Contribute

There are many ways to contribute to avante.nvim:

- 🐛 **Report bugs**: Help us identify and fix issues
- 💡 **Suggest features**: Share ideas for new functionality
- 📝 **Improve documentation**: Help others understand and use avante.nvim
- 🔧 **Submit code**: Fix bugs or implement new features
- 🌍 **Translate**: Help make avante.nvim accessible to more users
- ⭐ **Spread the word**: Share avante.nvim with others

## Getting Started

### Prerequisites

- Neovim v0.10+
- Git
- Rust and Cargo (for building from source)
- Node.js (for running tests)

### Setting Up Development Environment

1. **Fork the repository**

   Go to [github.com/yetone/avante.nvim](https://github.com/yetone/avante.nvim) and click "Fork".

2. **Clone your fork**

   ```bash
   git clone https://github.com/YOUR_USERNAME/avante.nvim.git
   cd avante.nvim
   ```

3. **Add upstream remote**

   ```bash
   git remote add upstream https://github.com/yetone/avante.nvim.git
   ```

4. **Install dependencies**

   ```bash
   make deps
   ```

5. **Build the project**

   ```bash
   make BUILD_FROM_SOURCE=true
   ```

### Running Tests

```bash
# Run Lua tests
make test-lua

# Run Rust tests
cd crates && cargo test

# Run all tests
make test
```

### Code Style

We use automated formatters to maintain consistent code style:

**Lua**
```bash
# Format Lua code
make format-lua

# Check Lua code
make lint-lua
```

**Rust**
```bash
# Format Rust code
cargo fmt

# Lint Rust code
cargo clippy
```

**Pre-commit Hooks**

Install pre-commit hooks to automatically format code:

```bash
pip install pre-commit
pre-commit install
```

## Making Changes

### Create a Branch

```bash
git checkout -b feature/my-new-feature
# or
git checkout -b fix/bug-description
```

### Make Your Changes

1. Write clear, concise code
2. Follow existing patterns and conventions
3. Add tests for new functionality
4. Update documentation as needed
5. Keep commits focused and atomic

### Commit Guidelines

We follow conventional commits:

```
feat: add support for new AI provider
fix: resolve sidebar rendering issue
docs: update installation instructions
test: add tests for configuration
refactor: simplify window management
```

Commit message format:
```
<type>(<scope>): <subject>

<body>

<footer>
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Submit a Pull Request

1. **Push your changes**

   ```bash
   git push origin feature/my-new-feature
   ```

2. **Create Pull Request**

   Go to GitHub and create a pull request from your fork to the main repository.

3. **Fill out PR template**

   - Describe what changes you made
   - Reference any related issues
   - Add screenshots for UI changes
   - List any breaking changes

4. **Wait for review**

   Maintainers will review your PR and may request changes.

## Development Guidelines

### Code Quality

- **Write tests**: All new features should have tests
- **Handle errors**: Provide meaningful error messages
- **Add type hints**: Use Lua annotations where appropriate
- **Document functions**: Add comments for complex logic
- **Keep it simple**: Prefer clarity over cleverness

### Performance

- **Avoid blocking operations**: Use async where appropriate
- **Cache when possible**: Don't repeat expensive operations
- **Profile before optimizing**: Measure before making changes
- **Test with large files**: Ensure it works at scale

### Compatibility

- **Support Neovim v0.10+**: Test against supported versions
- **Cross-platform**: Ensure it works on Linux, macOS, and Windows
- **Plugin compatibility**: Test with popular plugin managers

### Documentation

When adding features:

- Update relevant documentation files
- Add examples to help users understand
- Update the README if needed
- Consider adding to the website

## Project Structure

```
avante.nvim/
├── lua/                 # Lua source code
│   └── avante/
│       ├── api.lua      # Public API
│       ├── config.lua   # Configuration
│       ├── init.lua     # Entry point
│       └── ...
├── crates/              # Rust source code
│   ├── avante-tokenizers/
│   ├── avante-templates/
│   └── ...
├── tests/               # Test files
├── docs/                # Documentation (website)
├── scripts/             # Build and utility scripts
└── Makefile             # Build tasks
```

## Reporting Issues

### Before Reporting

1. **Search existing issues**: Check if it's already reported
2. **Try latest version**: Ensure you're on the latest version
3. **Reproduce the issue**: Verify it's reproducible
4. **Gather information**: Collect logs and system info

### Creating an Issue

Include:

- **Neovim version**: `:version`
- **OS and version**: e.g., Ubuntu 22.04, macOS 14.0
- **Plugin manager**: lazy.nvim, packer, etc.
- **Configuration**: Your avante.nvim config
- **Steps to reproduce**: Clear steps to reproduce the issue
- **Expected behavior**: What should happen
- **Actual behavior**: What actually happens
- **Logs**: Relevant error messages or logs

### Issue Template

```markdown
**Description**
Clear description of the issue.

**To Reproduce**
1. Open file X
2. Run command Y
3. See error

**Expected Behavior**
What you expected to happen.

**Screenshots**
If applicable, add screenshots.

**Environment**
- Neovim version:
- OS:
- Plugin manager:
- Configuration:

**Logs**
```
paste logs here
```
```

## Feature Requests

When requesting features:

- **Explain the use case**: Why is this needed?
- **Describe the solution**: How should it work?
- **Consider alternatives**: What other approaches exist?
- **Show examples**: Provide examples if helpful

## Getting Help

- 💬 **Discord**: [Join our Discord](https://discord.gg/QfnEFEdSjz)
- 🐛 **Issues**: [GitHub Issues](https://github.com/yetone/avante.nvim/issues)
- 📖 **Documentation**: [Official docs](/)

## Code Review Process

1. **Automated checks**: CI runs tests and linters
2. **Maintainer review**: A maintainer reviews the code
3. **Feedback**: You may need to make changes
4. **Approval**: Once approved, it will be merged
5. **Release**: Changes are included in the next release

## Recognition

Contributors are recognized in:

- GitHub contributors page
- Release notes
- Project README

## License

By contributing to avante.nvim, you agree that your contributions will be licensed under the Apache 2.0 License.

## Questions?

If you have questions about contributing, feel free to:

- Ask in our [Discord](https://discord.gg/QfnEFEdSjz)
- Open a [discussion](https://github.com/yetone/avante.nvim/discussions)
- Reach out to maintainers

Thank you for contributing to avante.nvim! 🎉
