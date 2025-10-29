# Project Instructions

## What are Project Instructions?

Project instructions allow you to provide project-specific context and guidelines to the AI through a markdown file (typically `avante.md`) placed in your project root. This file is automatically referenced during all interactions with avante.nvim.

## Why Use Project Instructions?

Project instructions enable:

- **Consistent coding style**: Enforce project-specific conventions across the team
- **Domain expertise**: Define the AI's role and expertise level for your project
- **Custom workflows**: Specify development practices unique to your project
- **Context awareness**: Help the AI understand your project's architecture and goals
- **Team alignment**: Share project knowledge with all developers

## Setup

### 1. Create the Instructions File

Create a file named `avante.md` in your project root:

```bash
cd /path/to/your/project
touch avante.md
```

### 2. Configure Custom File Name (Optional)

If you prefer a different file name, configure it in your avante setup:

```lua
require("avante").setup({
  instructions_file = ".avante.md",  -- or "AI_INSTRUCTIONS.md", etc.
})
```

### 3. Write Your Instructions

Edit `avante.md` with your project-specific guidelines (see examples below).

## Best Practices

### Structure Your Instructions

A well-structured `avante.md` file typically includes:

#### 1. Your Role

Define the AI's persona and expertise level:

```markdown
### Your Role

You are an expert senior software engineer specializing in [technology stack]. 
You have deep knowledge of [specific frameworks/tools] and understand best 
practices for [domain/industry]. You write clean, maintainable, and 
well-documented code. You prioritize code quality, performance, and security 
in all your recommendations.
```

#### 2. Your Mission

Clearly describe what the AI should focus on:

```markdown
### Your Mission

Your primary goal is to help build and maintain [project description]. You should:

- Provide code suggestions that follow our established patterns and conventions
- Help debug issues by analyzing code and suggesting solutions
- Assist with refactoring to improve code quality and maintainability
- Suggest optimizations for performance and scalability
- Ensure all code follows our security guidelines
- Help write comprehensive tests for new features
```

#### 3. Additional Sections

Consider adding:

- **Project Context**: Brief description of the project, its goals, and target users
- **Technology Stack**: List of technologies, frameworks, and tools used
- **Coding Standards**: Specific conventions, style guides, and patterns to follow
- **Architecture Guidelines**: How components should interact and be organized
- **Testing Requirements**: Testing strategies and coverage expectations
- **Security Considerations**: Specific security requirements or constraints

## Complete Example

Here's a comprehensive example for a web application:

```markdown
# Project Instructions for MyApp

## Your Role

You are an expert full-stack developer specializing in React, Node.js, and 
TypeScript. You understand modern web development practices and have extensive 
experience with our tech stack.

## Your Mission

Help build a scalable e-commerce platform by:

- Writing type-safe TypeScript code
- Following React best practices and hooks patterns
- Implementing RESTful APIs with proper error handling
- Ensuring responsive design with Tailwind CSS
- Writing comprehensive unit and integration tests

## Project Context

MyApp is a modern e-commerce platform targeting small businesses. We prioritize 
performance, accessibility, and user experience. The application serves 
thousands of concurrent users and handles sensitive payment information.

## Technology Stack

### Frontend
- React 18
- TypeScript 5.0+
- Tailwind CSS
- Vite
- React Router
- TanStack Query

### Backend
- Node.js 20+
- Express
- Prisma ORM
- PostgreSQL
- Redis (caching)

### Testing
- Jest
- React Testing Library
- Playwright (E2E)
- MSW (API mocking)

### Deployment
- Docker
- AWS (ECS, RDS, S3)
- GitHub Actions (CI/CD)

## Coding Standards

### TypeScript
- Use strict mode
- Prefer interfaces over types for objects
- Always specify return types for functions
- Use enums for constants with multiple values

### React
- Use functional components with hooks
- Prefer composition over inheritance
- Keep components small and focused (< 200 lines)
- Extract custom hooks for reusable logic
- Use React.memo() for expensive components

### Styling
- Use Tailwind utility classes
- Follow mobile-first approach
- Maintain consistent spacing (4px grid)
- Use CSS variables for theme colors

### Code Organization
- Feature-based folder structure
- Colocate tests with source files
- Keep utilities in shared folder
- One component per file

### Naming Conventions
- Components: PascalCase (UserProfile.tsx)
- Hooks: camelCase with 'use' prefix (useAuth.ts)
- Utilities: camelCase (formatDate.ts)
- Constants: UPPER_SNAKE_CASE (API_BASE_URL)

## Architecture Guidelines

### Component Structure
```
src/
  features/
    users/
      components/
      hooks/
      api/
      types/
      utils/
  shared/
    components/
    hooks/
    utils/
```

### State Management
- Use React Query for server state
- Use Context for global UI state
- Keep state as local as possible
- Avoid prop drilling (use composition)

### API Design
- RESTful endpoints
- Consistent error responses
- Proper HTTP status codes
- Request/response validation
- Rate limiting on all endpoints

## Testing Requirements

### Coverage Goals
- Unit tests: 80% minimum
- Integration tests: Critical paths
- E2E tests: User flows

### What to Test
- All business logic
- API endpoints
- Component interactions
- Error handling
- Edge cases

### Testing Patterns
- AAA pattern (Arrange, Act, Assert)
- Test user behavior, not implementation
- Mock external dependencies
- Use data-testid for element selection

## Security Considerations

### Authentication
- JWT tokens with refresh mechanism
- Secure password hashing (bcrypt)
- Rate limit login attempts
- Session timeout after 30 minutes

### Data Handling
- Validate all inputs
- Sanitize user content
- Use parameterized queries
- Encrypt sensitive data at rest

### API Security
- CORS configuration
- CSRF protection
- XSS prevention
- SQL injection prevention

## Performance Guidelines

- Lazy load routes and components
- Optimize images (WebP, lazy loading)
- Implement pagination for lists
- Cache API responses when appropriate
- Monitor bundle size (< 200KB initial)

## Error Handling

- User-friendly error messages
- Log errors to monitoring service
- Graceful degradation
- Retry logic for network requests
- Fallback UI for errors
```

## Shorter Example

For smaller projects, a simpler version works well:

```markdown
# Project Instructions

## Your Role
You are a Python expert working on a data science project.

## Technology Stack
- Python 3.11+
- pandas, numpy, scikit-learn
- Jupyter notebooks
- pytest

## Coding Standards
- Follow PEP 8
- Use type hints
- Write docstrings (Google style)
- Maximum line length: 88 characters (Black formatter)

## Testing
- Write unit tests for all functions
- Use pytest fixtures
- Aim for 80%+ coverage
```

## Language-Specific Examples

### Python/Django Project

```markdown
# Django Project Instructions

## Your Role
Expert Django developer specializing in REST APIs and web applications.

## Stack
- Python 3.11+
- Django 5.0
- Django REST Framework
- PostgreSQL
- Celery, Redis

## Standards
- Follow Django best practices
- Use class-based views
- Implement proper serializers
- Write migrations for all model changes
- Use Django's built-in authentication

## Testing
- Use Django TestCase
- Test models, views, and serializers
- Mock external services
```

### Go Project

```markdown
# Go Project Instructions

## Your Role
Expert Go developer building microservices.

## Stack
- Go 1.21+
- Gin framework
- GORM
- PostgreSQL

## Standards
- Follow Go conventions (gofmt, golint)
- Use interfaces for dependencies
- Proper error handling (no panics in prod)
- Write idiomatic Go code
- Use context for cancellation

## Testing
- Table-driven tests
- Use testify for assertions
- Mock external dependencies
- Benchmark performance-critical code
```

## Tips for Effective Instructions

### Be Specific

Instead of:
```markdown
Write clean code.
```

Write:
```markdown
- Functions should be < 50 lines
- Use meaningful variable names (not x, y, temp)
- Add JSDoc comments for complex functions
- Prefer pure functions when possible
```

### Include Examples

Show, don't just tell:

```markdown
## Error Handling

Bad:
```javascript
const data = await fetch(url)
```

Good:
```javascript
try {
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`)
  }
  const data = await response.json()
  return data
} catch (error) {
  console.error('Fetch failed:', error)
  throw error
}
```
```

### Keep It Updated

- Review and update instructions as the project evolves
- Add new patterns as you establish them
- Remove outdated guidelines
- Version control your `avante.md` file

### Make It Accessible

- Use clear, simple language
- Organize with headers and lists
- Keep it concise but comprehensive
- Link to external resources when helpful

## Advanced Usage

### Multiple Instruction Files

For monorepos or large projects:

```
project/
  avante.md                 # Root instructions
  frontend/
    avante.md              # Frontend-specific
  backend/
    avante.md              # Backend-specific
  mobile/
    avante.md              # Mobile-specific
```

Configure avante to check the current directory first:

```lua
require("avante").setup({
  instructions_file = "avante.md",
  use_nearest_instructions = true, -- Look in current dir, then parent dirs
})
```

### Template Variables

Use placeholders in your instructions:

```markdown
## Project: {{PROJECT_NAME}}
Version: {{VERSION}}
Environment: {{ENVIRONMENT}}
```

### Including External Files

Reference external documentation:

```markdown
## Architecture

See our [architecture documentation](./docs/architecture.md) for details.

## API Contracts

Refer to [OpenAPI spec](./api/openapi.yaml) for API contracts.
```

## Next Steps

- [Quick Start](/quickstart) - Get started with avante.nvim
- [Configuration](/configuration) - Customize your setup
- [Features](/features) - Explore all features

## Getting Help

- 📖 [Full Documentation](/)
- 🐛 [Report Issues](https://github.com/yetone/avante.nvim/issues)
- 💬 [Join Discord](https://discord.gg/QfnEFEdSjz)
