# Quick Start Guide

Get your wiki deployed to Vercel in 5 minutes!

## Prerequisites

- GitHub account
- Vercel account (free tier works great)

## Steps

### 1. Create GitHub Repository

1. Go to https://github.com/new
2. Repository name: `brainrot-catchers-wiki` (or your preferred name)
3. Choose Public or Private
4. **Important**: Don't check "Initialize with README"
5. Click "Create repository"

### 2. Initialize Git in Wiki Folder

Open PowerShell or Terminal in the `wiki` folder and run:

**PowerShell (Windows):**
```powershell
.\setup-github.ps1
```

**Bash (Mac/Linux):**
```bash
chmod +x setup-github.sh
./setup-github.sh
```

**Or manually:**
```bash
git init
git add .
git commit -m "Initial commit: Brainrot Catchers Wiki"
git branch -M main
```

### 3. Push to GitHub

Replace `YOUR_USERNAME` and `YOUR_REPO_NAME` with your actual GitHub username and repository name:

```bash
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
git push -u origin main
```

### 4. Deploy to Vercel

1. Go to https://vercel.com
2. Sign in with GitHub
3. Click "Add New..." → "Project"
4. Import your repository
5. Vercel will auto-detect Next.js - just click "Deploy"!
6. Wait 2-3 minutes for deployment
7. Your wiki is live! 🎉

## That's It!

Your wiki will automatically redeploy whenever you push changes to GitHub.

## Need More Details?

See [DEPLOYMENT.md](./DEPLOYMENT.md) for comprehensive instructions.

