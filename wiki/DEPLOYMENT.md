# Deployment Guide

This guide will walk you through setting up the Brainrot Catchers Wiki on GitHub and deploying it to Vercel.

## Step 1: Create GitHub Repository

1. Go to [GitHub](https://github.com) and sign in
2. Click the "+" icon in the top right → "New repository"
3. Name your repository (e.g., `brainrot-catchers-wiki`)
4. Choose visibility (Public or Private)
5. **DO NOT** initialize with README, .gitignore, or license (we already have these)
6. Click "Create repository"

## Step 2: Push Code to GitHub

Run these commands in the `wiki` folder:

```bash
# Make sure you're in the wiki directory
cd wiki

# Initialize git (if not already done)
git init

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit: Brainrot Catchers Wiki"

# Add your GitHub repository as remote (replace YOUR_USERNAME and REPO_NAME)
git remote add origin https://github.com/YOUR_USERNAME/REPO_NAME.git

# Or if using SSH:
# git remote add origin git@github.com:YOUR_USERNAME/REPO_NAME.git

# Push to GitHub
git branch -M main
git push -u origin main
```

## Step 3: Deploy to Vercel

### Option A: Using Vercel Dashboard (Recommended)

1. Go to [vercel.com](https://vercel.com) and sign in (use GitHub to sign in)
2. Click "Add New..." → "Project"
3. Import your GitHub repository
4. Vercel will auto-detect Next.js settings:
   - Framework Preset: **Next.js**
   - Root Directory: **./wiki** (if repo is at root) or leave blank if wiki is the repo root
   - Build Command: `npm run build`
   - Output Directory: `.next`
   - Install Command: `npm install`
5. Click "Deploy"
6. Wait for deployment to complete (usually 2-3 minutes)

### Option B: Using Vercel CLI

```bash
# Install Vercel CLI globally
npm i -g vercel

# Navigate to wiki folder
cd wiki

# Deploy
vercel

# Follow the prompts:
# - Set up and deploy? Yes
# - Which scope? (select your account)
# - Link to existing project? No
# - Project name? (press enter for default)
# - Directory? (press enter for current directory)
# - Override settings? No
```

## Step 4: Configure Custom Domain (Optional)

1. In Vercel dashboard, go to your project
2. Click "Settings" → "Domains"
3. Add your custom domain
4. Follow DNS configuration instructions

## Step 5: Environment Variables (If Needed)

If you need environment variables:

1. Go to Vercel dashboard → Your Project → Settings → Environment Variables
2. Add any required variables
3. Redeploy if needed

## Updating the Wiki

After making changes:

```bash
# Make your changes
# ...

# Commit changes
git add .
git commit -m "Description of changes"

# Push to GitHub
git push origin main
```

Vercel will automatically detect the push and redeploy your site!

## Troubleshooting

### Build Fails

- Check that all dependencies are in `package.json`
- Ensure `npm run build` works locally
- Check Vercel build logs for specific errors

### Data Not Updating

- Make sure to run `npm run extract` before committing if you updated Lua files
- Commit the updated `data/` folder

### Deployment Takes Too Long

- Check build logs in Vercel dashboard
- Ensure `node_modules` is in `.gitignore`
- Consider using Vercel's build cache

## Need Help?

- [Vercel Documentation](https://vercel.com/docs)
- [Next.js Deployment Guide](https://nextjs.org/docs/deployment)
- [GitHub Documentation](https://docs.github.com)

