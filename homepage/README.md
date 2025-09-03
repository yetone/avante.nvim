# avante.nvim Homepage

This is the official homepage for avante.nvim, built with Next.js 14 and TypeScript.

## Features

- 🌍 **Internationalization**: English and Chinese language support
- ⚡ **Performance**: Static site generation with optimal Core Web Vitals
- 📱 **Responsive**: Mobile-first design that works on all devices
- ♿ **Accessible**: WCAG 2.1 AA compliance
- 🎨 **Modern UI**: Beautiful design with Tailwind CSS and Framer Motion
- 📊 **Real-time Stats**: Live GitHub and Discord community statistics
- 🔍 **SEO Optimized**: Structured data and meta tags for search engines

## Getting Started

### Prerequisites

- Node.js 18+
- npm or yarn

### Installation

```bash
cd homepage
npm install
```

### Development

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to view the homepage.

### Building

```bash
npm run build
npm start
```

### Linting

```bash
npm run lint
npm run type-check
```

## Project Structure

```
homepage/
├── components/          # React components
│   ├── ui/             # Base UI components
│   ├── sections/       # Page sections
│   ├── Navigation.tsx  # Navigation component
│   └── Footer.tsx      # Footer component
├── pages/              # Next.js pages
│   ├── api/           # API routes
│   ├── _app.tsx       # App wrapper
│   ├── _document.tsx  # Document wrapper
│   └── index.tsx      # Homepage
├── lib/               # Utility functions
├── locales/           # Translation files
├── styles/            # Global styles
└── public/            # Static assets
```

## Features Implemented

### Homepage Sections

- **Hero Section**: Eye-catching introduction with animated text and CTAs
- **Features Section**: Core capabilities with interactive elements and comparison table
- **Installation Section**: Step-by-step guides for different plugin managers
- **Community Section**: Discord, GitHub, and sponsorship information with testimonials

### Technical Features

- **Static Site Generation**: Pre-rendered pages for optimal performance
- **API Integration**: Real-time GitHub and Discord statistics
- **Internationalization**: Full i18n support with Next.js built-in features
- **SEO Optimization**: Meta tags, structured data, and sitemap
- **Accessibility**: Keyboard navigation, screen reader support, and WCAG compliance
- **Performance**: Image optimization, code splitting, and caching strategies

## Deployment

The homepage is configured for static export and can be deployed to:

- **Vercel**: Automatic deployments with GitHub integration
- **Netlify**: Static hosting with form handling
- **GitHub Pages**: Free hosting for open source projects
- **Custom hosting**: Any static file server

### Environment Variables

For production deployment, you may want to configure:

- `GA_MEASUREMENT_ID`: Google Analytics tracking ID
- `NODE_ENV`: Environment (development/production)

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Test thoroughly: `npm run lint && npm run type-check`
5. Commit your changes: `git commit -m 'Add amazing feature'`
6. Push to the branch: `git push origin feature/amazing-feature`
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the main project LICENSE file for details.