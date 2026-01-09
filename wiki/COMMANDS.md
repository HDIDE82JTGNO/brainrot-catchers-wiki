# Command Reference

Quick reference for common commands when working with the wiki.

## Development

```bash
# Start development server
npm run dev

# Build for production
npm run build

# Start production server
npm run start

# Run linter
npm run lint

# Extract game data from Lua files
npm run extract

# Sync game data from parent directory
npm run sync-game-data
```

## Git Commands

```bash
# Initialize git repository (if not already done)
git init

# Stage all files
git add .

# Commit changes
git commit -m "Your commit message"

# Create/switch to main branch
git branch -M main

# Add remote repository
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git

# Push to GitHub
git push -u origin main

# Check status
git status

# View changes
git diff
```

## Deployment

### First Time Setup

```bash
# 1. Initialize git
git init
git add .
git commit -m "Initial commit: Brainrot Catchers Wiki"
git branch -M main

# 2. Add GitHub remote (replace with your repo URL)
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git

# 3. Push to GitHub
git push -u origin main

# 4. Then deploy via Vercel dashboard
```

### Updating After Changes

```bash
# Make your changes, then:
git add .
git commit -m "Description of changes"
git push origin main

# Vercel will automatically redeploy!
```

## Vercel CLI (Optional)

```bash
# Install Vercel CLI
npm i -g vercel

# Deploy
vercel

# Deploy to production
vercel --prod
```

## Troubleshooting

```bash
# Clear node_modules and reinstall
rm -rf node_modules package-lock.json
npm install

# Clear Next.js cache
rm -rf .next
npm run build

# Check Node version
node --version  # Should be 18+

# Check npm version
npm --version
```

