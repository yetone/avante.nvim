# avante.nvim Homepage

<<<<<<< HEAD
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
=======
This is the official homepage for avante.nvim - AI-Powered Code Assistance for Neovim.

## Tech Stack

- **Framework**: Next.js 15 with App Router
- **Styling**: Tailwind CSS
- **Internationalization**: next-intl (English and Chinese)
- **Deployment**: Static site generation for GitHub Pages

## Development
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)

```bash
# Install dependencies
npm install

<<<<<<< HEAD
# Start development server
=======
# Run development server
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)
npm run dev

# Build for production
npm run build
<<<<<<< HEAD

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
=======
```

The development server will start at `http://localhost:3000`
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)

## Project Structure

```
homepage/
<<<<<<< HEAD
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
=======
├── app/
│   ├── [locale]/          # Internationalized routes
│   │   ├── layout.tsx     # Root layout with i18n
│   │   └── page.tsx       # Homepage
│   └── globals.css        # Global styles
├── components/            # React components
│   ├── Navigation.tsx     # Navigation bar
│   ├── HeroSection.tsx    # Hero section
│   ├── FeaturesSection.tsx # Features showcase
│   ├── InstallationSection.tsx # Installation guide
│   ├── Footer.tsx         # Footer
│   └── CodeBlock.tsx      # Code block with copy functionality
├── lib/                   # Utility functions
│   ├── github.ts          # GitHub API integration
│   └── utils.ts           # Helper utilities
├── messages/              # i18n translations
│   ├── en.json           # English translations
│   └── zh.json           # Chinese translations
└── public/               # Static assets
```

## Features

- ✅ Responsive design (mobile-first)
- ✅ Dark mode optimized
- ✅ Internationalization (English/Chinese)
- ✅ GitHub API integration for live stats
- ✅ SEO optimized with meta tags
- ✅ Static site generation
- ✅ Copy-to-clipboard functionality
- ✅ Smooth scrolling navigation

## Deployment

This site is built as a static export and can be deployed to:

- GitHub Pages
- Vercel
- Netlify
- Cloudflare Pages
- Any static hosting service

To build for deployment:

```bash
npm run build
```

The static files will be generated in the `out/` directory.

## License

MIT - Same as avante.nvim
>>>>>>> c8dfc81 (feat(homepage): implement complete Next.js homepage with i18n support)
