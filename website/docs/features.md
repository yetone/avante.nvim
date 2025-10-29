# Features

## Core Features

### 🤖 AI-Powered Code Assistance

Interact with AI to ask questions about your current code file and receive intelligent suggestions for improvement or modification.

- **Context-aware suggestions**: The AI understands your entire file context
- **Multi-turn conversations**: Have back-and-forth discussions about your code
- **Code explanations**: Ask the AI to explain complex code sections
- **Bug detection**: Get help identifying and fixing bugs

<div style="margin: 2rem 0;">
  <video controls style="width: 100%; border-radius: 8px;">
    <source src="https://github.com/user-attachments/assets/86140bfd-08b4-483d-a887-1b701d9e37dd" type="video/mp4">
  </video>
</div>

### ⚡ One-Click Application

Quickly apply the AI's suggested changes to your source code with a single command, streamlining the editing process and saving time.

- **Instant code changes**: Apply suggestions with a single keystroke
- **Diff preview**: See exactly what will change before applying
- **Undo support**: Easy rollback if needed
- **Batch operations**: Apply multiple suggestions at once

### 📝 Project-Specific Instructions

Customize AI behavior by adding a markdown file (`avante.md` by default) in the project root. This file is automatically referenced during workspace changes.

Benefits:
- **Consistent coding style**: Enforce project-specific conventions
- **Domain expertise**: Define the AI's role and expertise level
- **Custom workflows**: Specify project-specific development practices
- **Team alignment**: Share project context with all developers

See [Project Instructions](/project-instructions) for detailed setup.

## Advanced Features

### 🧘 Zen Mode

A revolutionary way to interact with AI coding assistants that combines the power of modern AI agents with the efficiency of Neovim.

Zen Mode provides:
- **Full terminal-based workflow**: No context switching required
- **Vim muscle memory**: Use all your familiar Vim operations
- **Rich plugin ecosystem**: Leverage thousands of Neovim plugins
- **ACP support**: All capabilities of claude code / gemini-cli / codex

Learn more about [Zen Mode](/zen-mode).

### 🔌 Multiple AI Provider Support

avante.nvim supports a wide range of AI providers out of the box:

- **Claude** (Anthropic) - Recommended
- **OpenAI** (GPT-4, GPT-3.5)
- **Azure OpenAI**
- **GitHub Copilot**
- **Google Gemini**
- **Cohere**
- **Moonshot**
- **DeepSeek**
- **Groq**
- **And many more...**

Each provider can be configured with custom endpoints, models, and parameters.

### 🎨 Customizable UI

Beautiful and highly customizable interface that seamlessly integrates with your Neovim setup:

- **Window positioning**: Flexible sidebar or floating window
- **Color schemes**: Match your Neovim theme
- **Layout options**: Customize split sizes and orientations
- **Keybindings**: Fully remappable keybindings

### 📷 Image Support

Paste and reference images in your AI conversations:

- **Screenshot pasting**: Paste images directly from clipboard
- **Image analysis**: AI can analyze and describe images
- **Diagram generation**: Get help with architecture diagrams
- **Visual debugging**: Share screenshots for debugging help

Requires the `img-clip.nvim` plugin.

### 🔍 Code Search and Navigation

Advanced code understanding capabilities:

- **Repository-wide context**: AI understands your entire codebase
- **Symbol search**: Find and understand symbols across files
- **Reference finding**: Locate all usages of functions/variables
- **Smart suggestions**: Context from related files

### 🧪 Test Generation

AI-assisted test writing:

- **Unit test generation**: Generate comprehensive test cases
- **Test fixtures**: Create test data and mocks
- **Edge case detection**: Identify edge cases to test
- **Test improvement**: Enhance existing test coverage

### 📚 Documentation

Automated documentation generation:

- **Function documentation**: Generate JSDoc, docstrings, etc.
- **README updates**: Keep documentation in sync with code
- **API documentation**: Document interfaces and APIs
- **Code comments**: Add explanatory comments

### 🔄 Refactoring

AI-powered code refactoring:

- **Extract methods**: Identify and extract reusable code
- **Rename symbols**: Intelligent renaming across files
- **Code simplification**: Simplify complex code structures
- **Pattern application**: Apply design patterns

### 🌐 Multi-Language Support

Full support for all major programming languages:

- **JavaScript/TypeScript**
- **Python**
- **Go**
- **Rust**
- **Java/Kotlin**
- **C/C++**
- **Ruby**
- **PHP**
- **And many more...**

### 💾 Conversation History

Never lose your AI interactions:

- **Session persistence**: Conversations saved across sessions
- **History search**: Find previous discussions
- **Conversation export**: Export conversations for sharing
- **Context restoration**: Resume where you left off

## Keyboard Shortcuts

Default keybindings (all customizable):

- `<leader>aa` - Toggle avante sidebar
- `<leader>ar` - Refresh AI suggestions
- `<leader>ae` - Edit selected code with AI
- `<leader>ac` - Clear conversation history
- `<CR>` (in sidebar) - Apply suggestion
- `<Tab>` - Cycle through suggestions
- `q` - Close sidebar

## Performance

avante.nvim is designed for performance:

- **Async operations**: Non-blocking AI requests
- **Lazy loading**: Minimal startup impact
- **Efficient caching**: Smart caching of AI responses
- **Binary optimizations**: Rust-based performance-critical components

## Privacy & Security

- **Local processing**: Code analysis happens locally when possible
- **Configurable API endpoints**: Use your own API endpoints
- **No telemetry**: Your code never leaves your control
- **API key security**: Environment-based key management

## Extensibility

avante.nvim is built to be extended:

- **Custom providers**: Add your own AI providers
- **Plugin hooks**: Integrate with other plugins
- **Custom templates**: Define your own prompt templates
- **Event callbacks**: React to avante events

## Next Steps

- [Configuration Guide](/configuration) - Customize your setup
- [Project Instructions](/project-instructions) - Set up project-specific behavior
- [Zen Mode](/zen-mode) - Learn about the Zen Mode workflow
