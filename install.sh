#!/bin/bash
# Install appstore-skill into the current project.
# Usage: curl -fsSL https://raw.githubusercontent.com/mikwiseman/appstore-skill/main/install.sh | bash

set -e

REPO="https://raw.githubusercontent.com/mikwiseman/appstore-skill/main"

if [ ! -d "fastlane" ]; then
  echo "Error: No fastlane/ directory found."
  echo "Run this from the root of an iOS project that uses fastlane."
  exit 1
fi

mkdir -p .claude/commands scripts

echo "Downloading appstore skill..."
curl -fsSL "$REPO/.claude/commands/appstore.md" -o .claude/commands/appstore.md

echo "Downloading preview script..."
curl -fsSL "$REPO/scripts/preview_appstore.py" -o scripts/preview_appstore.py
chmod +x scripts/preview_appstore.py

echo ""
echo "Installed:"
echo "  .claude/commands/appstore.md"
echo "  scripts/preview_appstore.py"
echo ""
echo "Usage in Claude Code:"
echo "  /appstore preview    — generate HTML preview dashboard"
echo "  /appstore metadata   — generate App Store metadata"
echo "  /appstore full       — run the entire pipeline"
