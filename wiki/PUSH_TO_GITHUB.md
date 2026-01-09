# Push to GitHub - Final Steps

✅ **Git repository initialized and committed!**

Your wiki is ready to push to GitHub. Follow these steps:

## Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. Repository name: `brainrot-catchers-wiki` (or your preferred name)
3. Choose **Public** or **Private**
4. **IMPORTANT**: Do NOT check "Initialize with README", "Add .gitignore", or "Choose a license"
5. Click **"Create repository"**

## Step 2: Copy Your Repository URL

After creating the repository, GitHub will show you a URL like:
- `https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git`
- Or: `git@github.com:YOUR_USERNAME/YOUR_REPO_NAME.git`

## Step 3: Push to GitHub

Open PowerShell in the `wiki` folder and run:

```powershell
# Replace YOUR_USERNAME and YOUR_REPO_NAME with your actual values
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git

# Push to GitHub
git push -u origin main
```

**Example:**
```powershell
git remote add origin https://github.com/johndoe/brainrot-catchers-wiki.git
git push -u origin main
```

## That's It! 🎉

Your wiki is now on GitHub! You can view it at:
`https://github.com/YOUR_USERNAME/YOUR_REPO_NAME`

## Next Steps (Optional)

- Deploy to Vercel: Import your GitHub repository at https://vercel.com
- Set up GitHub Pages: Go to repository Settings → Pages
- Add collaborators: Settings → Collaborators

## Troubleshooting

**If you get "remote origin already exists":**
```powershell
git remote remove origin
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
```

**If you get authentication errors:**
- Use GitHub Personal Access Token instead of password
- Or set up SSH keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

