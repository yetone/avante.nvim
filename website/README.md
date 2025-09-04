# avante.nvim Homepage

This is the homepage for avante.nvim built with Next.js 14, React 18, and Tailwind CSS.

## Features

- ✨ Modern, responsive design
- 🌙 Dark mode support
- 🚀 Optimized for performance (target: 90+ Lighthouse score)
- 🌐 Multi-language support (English/Chinese)
- 📱 Mobile-first responsive design
- ♿ WCAG 2.1 AA accessibility compliance
- 🔍 SEO optimized

## Getting Started

### Prerequisites

- Node.js 18.17 or later
- npm, yarn, or pnpm

### Installation

1. Navigate to the website directory:
```bash
cd website
```

2. Install dependencies:
```bash
npm install
# or
yarn install
# or
pnpm install
```

3. Start the development server:
```bash
npm run dev
# or
yarn dev
# or
pnpm dev
```

4. Open [http://localhost:3000](http://localhost:3000) in your browser.

### Building for Production

```bash
npm run build
# or
yarn build
# or
pnpm build
```

The built files will be in the `out` directory, ready for static hosting.

## Deployment

This site is configured for static export and can be deployed to:

- GitHub Pages
- Vercel
- Netlify
- Any static hosting provider

### Recommended: Vercel

1. Connect your GitHub repository to Vercel
2. Set the root directory to `website`
3. Vercel will automatically detect the Next.js configuration
4. Deploy!

## Project Structure

```
website/
├── app/
│   ├── globals.css      # Global styles
│   ├── layout.tsx       # Root layout component
│   └── page.tsx         # Homepage
├── components/
│   ├── Header.tsx       # Navigation header
│   ├── HeroSection.tsx  # Hero section with CTA
│   ├── FeaturesSection.tsx  # Features and comparison
│   ├── InstallationSection.tsx # Installation guides
│   ├── CommunitySection.tsx    # Community and testimonials
│   └── Footer.tsx       # Footer with links
├── public/              # Static assets
├── next.config.mjs      # Next.js configuration
├── tailwind.config.js   # Tailwind CSS configuration
└── tsconfig.json        # TypeScript configuration
```

## Performance Targets

- Lighthouse Performance: 90+
- First Contentful Paint: <2s
- Largest Contentful Paint: <2.5s
- Cumulative Layout Shift: <0.1

## Accessibility

This site is built with accessibility in mind:

- Semantic HTML structure
- ARIA labels where needed
- Keyboard navigation support
- Screen reader compatibility
- High contrast color schemes
- Alternative text for images

## Contributing

1. Make your changes in the `website` directory
2. Test locally with `npm run dev`
3. Build and test with `npm run build`
4. Submit a pull request

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](../LICENSE) file for details.
