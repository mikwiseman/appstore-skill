# appstore-skill

Claude Code skill that takes an iOS project from zero to App Store. Generates fastlane structure, metadata (with Exa SEO research), screenshots (Gemini + Playwright), HTML preview, and uploads to App Store Connect.

## Modes

- `/appstore` -- full pipeline
- `/appstore setup` -- create fastlane directory structure
- `/appstore metadata` -- generate metadata with SEO research
- `/appstore screenshots` -- simulator capture + AI backgrounds + compose
- `/appstore preview` -- HTML dashboard with all metadata and screenshots
- `/appstore upload` -- upload to App Store Connect via fastlane

## Structure

- `install.sh` -- curl-pipe installer, copies skill + preview script into user's project
- `scripts/` -- preview dashboard generator (Python)
- `LICENSE` -- MIT

## Key Details

- macOS + Xcode + Python 3.9+ required
- Optional: GEMINI_API_KEY, Exa MCP, fastlane CLI, Playwright
- Each optional dep degrades gracefully when absent
- UDID-based simulator selection (not names)
- Idempotent -- never overwrites existing fastlane files
