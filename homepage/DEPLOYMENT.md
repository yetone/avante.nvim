# Deployment Guide

This guide covers deploying the avante.nvim homepage to various hosting platforms.

## Pre-deployment Checklist

1. **Environment Variables**
   - `NEXT_PUBLIC_GA_MEASUREMENT_ID`: Google Analytics measurement ID (optional)
   - `NODE_ENV`: Set to `production` for production builds

2. **Build and Test**
   ```bash
   cd homepage
   npm install
   npm run lint
   npm run type-check
   npm run build
   ```

3. **Performance Check**
   - Run Lighthouse audit
   - Check Core Web Vitals
   - Verify image optimization

## Deployment Options

### 1. Vercel (Recommended)

Vercel provides the best integration for Next.js applications.

1. **Connect Repository**
   - Link your GitHub repository to Vercel
   - Set build settings:
     - Framework: Next.js
     - Root Directory: `homepage`
     - Build Command: `npm run build`
     - Output Directory: `.next`

2. **Environment Variables**
   ```
   NEXT_PUBLIC_GA_MEASUREMENT_ID=G-XXXXXXXXXX
   ```

3. **Custom Domain**
   - Add `avante.nvim.dev` or your preferred domain
   - Configure DNS records as instructed

### 2. Netlify

1. **Site Settings**
   - Build command: `npm run build`
   - Publish directory: `out`
   - Base directory: `homepage`

2. **netlify.toml Configuration**
   ```toml
   [build]
   base = "homepage"
   command = "npm run build"
   publish = "out"

   [[headers]]
   for = "/*"
   [headers.values]
     X-Frame-Options = "DENY"
     X-Content-Type-Options = "nosniff"
     Referrer-Policy = "origin-when-cross-origin"

   [[headers]]
   for = "/_next/static/*"
   [headers.values]
     Cache-Control = "public, max-age=31536000, immutable"
   ```

### 3. GitHub Pages

1. **GitHub Actions Workflow**
   Create `.github/workflows/deploy.yml`:
   ```yaml
   name: Deploy to GitHub Pages

   on:
     push:
       branches: [ main ]
       paths: [ 'homepage/**' ]

   jobs:
     deploy:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4

         - name: Setup Node.js
           uses: actions/setup-node@v4
           with:
             node-version: '18'
             cache: 'npm'
             cache-dependency-path: homepage/package-lock.json

         - name: Install dependencies
           run: |
             cd homepage
             npm ci

         - name: Build
           run: |
             cd homepage
             npm run build

         - name: Deploy
           uses: peaceiris/actions-gh-pages@v3
           with:
             github_token: ${{ secrets.GITHUB_TOKEN }}
             publish_dir: homepage/out
   ```

### 4. AWS S3 + CloudFront

1. **S3 Bucket Setup**
   - Create S3 bucket for static hosting
   - Enable public read access
   - Configure bucket policy

2. **CloudFront Distribution**
   - Create distribution pointing to S3 bucket
   - Configure custom domain
   - Enable compression

3. **Deploy Script**
   ```bash
   cd homepage
   npm run build
   aws s3 sync out/ s3://your-bucket-name --delete
   aws cloudfront create-invalidation --distribution-id XXXXX --paths "/*"
   ```

## Performance Optimization

### 1. Image Optimization
- Use Next.js `Image` component
- Configure image domains in `next.config.js`
- Enable modern formats (AVIF, WebP)

### 2. Bundle Analysis
```bash
npm install --save-dev @next/bundle-analyzer
```

Add to `next.config.js`:
```javascript
const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true',
});

module.exports = withBundleAnalyzer(nextConfig);
```

Run analysis:
```bash
ANALYZE=true npm run build
```

### 3. Caching Strategy
- Static assets: 1 year cache
- API routes: 1 hour with stale-while-revalidate
- HTML: No cache (handled by ISR)

## Monitoring

### 1. Google Analytics
- Configure measurement ID
- Monitor Core Web Vitals
- Track user interactions

### 2. Error Monitoring
Consider adding Sentry or similar:
```bash
npm install @sentry/nextjs
```

### 3. Performance Monitoring
- Use Vercel Analytics
- Monitor Lighthouse scores
- Track page load times

## Security Headers

The following security headers are automatically configured:
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`

## Troubleshooting

### Common Issues

1. **Build Failures**
   - Check Node.js version (18+)
   - Verify all dependencies are installed
   - Check TypeScript errors

2. **Image Loading Issues**
   - Verify image domains in `next.config.js`
   - Check image file sizes
   - Ensure proper image formats

3. **Performance Issues**
   - Run bundle analyzer
   - Optimize images
   - Check for large dependencies

### Support

For deployment issues:
1. Check the build logs
2. Verify environment variables
3. Test locally first
4. Contact the hosting provider support

## Continuous Integration

### Automated Testing
```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: |
          cd homepage
          npm ci
          npm run lint
          npm run type-check
          npm run build
```

This ensures code quality and prevents deployment of broken builds.
