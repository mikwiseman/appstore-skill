#!/bin/bash
# Install appstore-skill into the current project.
# Usage: curl -fsSL https://raw.githubusercontent.com/mikwiseman/appstore-skill/main/install.sh | bash

set -e

REPO="https://raw.githubusercontent.com/mikwiseman/appstore-skill/main"

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
echo "IMPORTANT: Start a new Claude Code session to use the skill."
echo "Skills are loaded at startup — /appstore won't work in the current session."
echo ""
echo "Usage (in a NEW Claude Code session):"
echo "  /appstore             — full pipeline (zero to App Store)"
echo "  /appstore setup       — create fastlane/ structure from scratch"
echo "  /appstore metadata    — generate App Store metadata with SEO research"
echo "  /appstore screenshots — capture + AI backgrounds + compose + export"
echo "  /appstore preview     — generate HTML preview dashboard"
echo "  /appstore upload      — upload to App Store Connect"
