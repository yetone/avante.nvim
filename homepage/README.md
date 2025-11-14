# avante.nvim Homepage

Modern, responsive homepage for avante.nvim - an AI-powered code assistance plugin for Neovim.

## Features

- 🌐 **Internationalization**: Full support for English and Chinese
- 📱 **Responsive Design**: Mobile-first approach with smooth animations
- ⚡ **Static Site Generation**: Fast loading with pre-rendered content
- 🎨 **Dark Mode**: Developer-friendly dark theme
- 📊 **Live Stats**: Real-time GitHub and Discord statistics
- ♿ **Accessible**: WCAG 2.1 AA compliant
- 🔍 **SEO Optimized**: Meta tags and structured data for search engines

## Getting Started

### Prerequisites

- Node.js 18+
- npm, yarn, or pnpm

### Installation

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Run tests
npm test
```

### Development

The development server will start at `http://localhost:3000`. The site supports hot reloading for rapid development.

### Building

The build process creates a static export in the `out/` directory, which can be deployed to any static hosting service:

```bash
npm run build
```

## Project Structure

```
homepage/
├── components/        # React components
│   ├── ui/           # Reusable UI components
│   └── Navigation.tsx
├── lib/              # Utility functions and API clients
├── locales/          # Translation files (en.json, zh.json)
├── pages/            # Next.js pages and API routes
│   ├── api/         # API endpoints
│   └── index.tsx    # Main homepage
├── styles/           # Global styles
└── __tests__/        # Test files
```

## Testing

Tests are written using Jest and React Testing Library:

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch
```

## Deployment

The homepage can be deployed to:

- **GitHub Pages**: Set up GitHub Actions workflow
- **Vercel**: Connect repository for automatic deployments
- **Netlify**: Drop the `out/` folder or connect repository
- **Cloudflare Pages**: Connect repository for edge deployments

## Technologies

- **Next.js 14**: React framework with static site generation
- **TypeScript**: Type-safe development
- **Tailwind CSS**: Utility-first CSS framework
- **Jest**: Testing framework
- **React Testing Library**: Component testing utilities

## License

This project is part of avante.nvim and is licensed under Apache 2.0.
