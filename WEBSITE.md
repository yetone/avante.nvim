# Official Website

This repository includes an official website for avante.nvim, built with VitePress and hosted on GitHub Pages.

## Website URL

🌐 **[https://yetone.github.io/avante.nvim/](https://yetone.github.io/avante.nvim/)**

## Local Development

To work on the website locally:

```bash
# Navigate to the website directory
cd website

# Install dependencies
npm install

# Start the development server
npm run dev
```

The site will be available at `http://localhost:5173/avante.nvim/`

## Building

To build the static site:

```bash
cd website
npm run build
```

To preview the built site:

```bash
npm run preview
```

## Deployment

The website is automatically deployed to GitHub Pages when changes are pushed to the `main` branch. The deployment is handled by the `.github/workflows/deploy-website.yml` workflow.

### Manual Deployment

If you need to manually deploy:

1. Ensure GitHub Pages is enabled in repository settings
2. Set the source to "GitHub Actions"
3. Push changes to trigger the workflow, or manually run the workflow from the Actions tab

## Directory Structure

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

## Updating Documentation

When updating the website:

1. Edit the relevant markdown files in `website/docs/`
2. Test locally with `npm run dev`
3. Build to verify: `npm run build`
4. Commit and push changes
5. The deployment workflow will automatically publish the updates

## VitePress Configuration

The VitePress configuration is in `website/docs/.vitepress/config.mts`. Key settings:

- **title**: Site title
- **description**: Site description
- **base**: Base URL path (`/avante.nvim/`)
- **themeConfig**: Navigation, sidebar, search, etc.

## Adding New Pages

1. Create a new `.md` file in `website/docs/`
2. Update the sidebar configuration in `config.mts`
3. Add navigation links if needed
4. Test locally and deploy

## Troubleshooting

### Build Fails

- Ensure all dependencies are installed: `npm install`
- Check for markdown syntax errors
- Verify all internal links are correct

### Website Not Updating

- Check the GitHub Actions workflow status
- Ensure GitHub Pages is configured correctly
- Clear browser cache

### Local Preview Issues

- Stop and restart the dev server
- Clear VitePress cache: `rm -rf website/docs/.vitepress/cache`
- Reinstall dependencies: `rm -rf node_modules && npm install`

## Resources

- [VitePress Documentation](https://vitepress.dev/)
- [GitHub Pages Documentation](https://docs.github.com/en/pages)
- [Markdown Guide](https://www.markdownguide.org/)
