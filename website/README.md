# avante.nvim Official Website

This directory contains the official website for avante.nvim built with VitePress.

## Development

Install dependencies:

```bash
npm install
```

Run development server:

```bash
npm run dev
```

The site will be available at http://localhost:5173

## Build

Build the static site:

```bash
npm run build
```

Preview the built site:

```bash
npm run preview
```

## Deployment

The site is automatically deployed to GitHub Pages when changes are pushed to the main branch.

## Structure

```
website/
├── docs/
│   ├── .vitepress/
│   │   └── config.mts          # VitePress configuration
│   ├── index.md                # Homepage
│   ├── installation.md         # Installation guide
│   ├── features.md             # Features page
│   ├── configuration.md        # Configuration guide
│   ├── quickstart.md           # Quick start guide
│   ├── zen-mode.md            # Zen Mode documentation
│   ├── project-instructions.md # Project instructions guide
│   ├── contributing.md         # Contributing guide
│   └── sponsorship.md         # Sponsorship page
├── package.json
└── README.md
```

## Contributing

See the main repository [Contributing Guide](../CONTRIBUTING.md) for details on how to contribute to the website.
