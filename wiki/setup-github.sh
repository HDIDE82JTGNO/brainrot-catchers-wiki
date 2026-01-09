#!/bin/bash

# Setup script for creating a separate GitHub repository for the wiki

echo "🚀 Setting up Brainrot Catchers Wiki for GitHub deployment"
echo ""

# Check if git is initialized
if [ -d ".git" ]; then
    echo "⚠️  Git repository already exists in this folder."
    echo "   This will create a nested git repository."
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "📦 Initializing git repository..."
    git init
fi

echo ""
echo "📝 Adding files to git..."
git add .

echo ""
echo "✅ Files staged. Ready to commit!"
echo ""
echo "Next steps:"
echo "1. Create a new repository on GitHub (don't initialize with README)"
echo "2. Run these commands:"
echo ""
echo "   git commit -m 'Initial commit: Brainrot Catchers Wiki'"
echo "   git branch -M main"
echo "   git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git"
echo "   git push -u origin main"
echo ""
echo "3. Then deploy to Vercel by importing your GitHub repository"
echo ""
echo "📖 See DEPLOYMENT.md for detailed instructions"

