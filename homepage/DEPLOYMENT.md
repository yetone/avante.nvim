# Deployment Guide

## GitHub Actions Workflow

The GitHub Actions workflow file for automated deployment is located at:
```
.github/workflows/deploy-homepage.yml
```

**Important Note**: This file was created but could not be pushed to the repository due to GitHub token permissions. The Personal Access Token used does not have the `workflow` scope required to create or modify workflow files.

### To Add the Workflow

The repository owner or an admin with appropriate permissions should:

1. Copy the workflow file from your local repository at `.github/workflows/deploy-homepage.yml`
2. Or manually create the file in GitHub with the following content:

```yaml
name: Deploy Homepage

on:
  push:
    branches:
      - main
    paths:
      - 'homepage/**'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./homepage

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: ./homepage/package-lock.json

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./homepage/out

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

3. Commit and push this file to enable automated deployment

### Enable GitHub Pages

Before the workflow can deploy, GitHub Pages must be enabled:

1. Go to repository Settings > Pages
2. Under "Source", select "GitHub Actions"
3. Save the settings

The homepage will be automatically deployed to GitHub Pages whenever changes are pushed to the `homepage/` directory on the main branch.

## Manual Deployment

If you prefer not to use GitHub Actions, you can manually deploy the static site:

### Build the Site

```bash
cd homepage
npm install
npm run build
```

The static files will be generated in `homepage/out/`

### Deploy to Any Static Host

You can deploy the `homepage/out/` directory to:

- **GitHub Pages**: Upload the contents to the `gh-pages` branch
- **Vercel**: Connect your GitHub repository and select `homepage` as the root directory
- **Netlify**: Drag and drop the `out` folder or connect via Git
- **Cloudflare Pages**: Connect via Git and configure build settings
- **Any static host**: Upload the files via FTP/SFTP or hosting control panel

## Configuration

All configuration is in `homepage/next.config.js`:

- `output: 'export'` enables static site generation
- `basePath` can be configured for subdirectory hosting
- `images.unoptimized` is required for static export

## Testing Locally

```bash
cd homepage
npm run dev
```

Visit `http://localhost:3000` to see the homepage.

## Building for Production

```bash
cd homepage
npm run build
```

Test the production build locally:

```bash
cd out
python3 -m http.server 8000
```

Visit `http://localhost:8000` to view the production build.
