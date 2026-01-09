# PowerShell setup script for creating a separate GitHub repository for the wiki

Write-Host "🚀 Setting up Brainrot Catchers Wiki for GitHub deployment" -ForegroundColor Cyan
Write-Host ""

# Check if git is initialized
if (Test-Path ".git") {
    Write-Host "⚠️  Git repository already exists in this folder." -ForegroundColor Yellow
    Write-Host "   This will create a nested git repository."
    $response = Read-Host "Continue? (y/n)"
    if ($response -ne "y" -and $response -ne "Y") {
        exit
    }
} else {
    Write-Host "📦 Initializing git repository..." -ForegroundColor Green
    git init
}

Write-Host ""
Write-Host "📝 Adding files to git..." -ForegroundColor Green
git add .

Write-Host ""
Write-Host "✅ Files staged. Ready to commit!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Create a new repository on GitHub (don't initialize with README)"
Write-Host "2. Run these commands:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   git commit -m 'Initial commit: Brainrot Catchers Wiki'"
Write-Host "   git branch -M main"
Write-Host "   git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git"
Write-Host "   git push -u origin main"
Write-Host ""
Write-Host "3. Then deploy to Vercel by importing your GitHub repository"
Write-Host ""
Write-Host "📖 See DEPLOYMENT.md for detailed instructions" -ForegroundColor Cyan

