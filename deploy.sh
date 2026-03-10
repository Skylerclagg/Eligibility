#!/bin/bash
# Deploy Flutter web build to gh-pages branch

set -e

# Build the Flutter web app
echo "Building Flutter web app..."
flutter build web --base-href /Eligibility/

# Save the build output to a temp directory
TEMP_DIR=$(mktemp -d)
cp -r build/web/* "$TEMP_DIR"

# Switch to gh-pages branch
echo "Switching to gh-pages branch..."
git stash --include-untracked
git checkout gh-pages

# Clear old files and copy new build
echo "Updating gh-pages with new build..."
git rm -rf . 2>/dev/null || true
cp -r "$TEMP_DIR"/* .
rm -rf "$TEMP_DIR"

# Commit and push
git add -A
git commit -m "Deploy web build $(date '+%Y-%m-%d %H:%M:%S')"
echo "Pushing to gh-pages..."
git push origin gh-pages

# Switch back to main
echo "Switching back to main..."
git checkout main
git stash pop 2>/dev/null || true

echo "Deploy complete!"
