# appstore-skill

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill for managing App Store metadata, screenshots, preview, and upload via [fastlane](https://fastlane.tools).

Works with any iOS project that uses fastlane. Auto-detects locales, app name, and app icon from your project.

## What it does

- **`/appstore metadata`** — Reads your codebase and generates all `fastlane/metadata/` files (name, subtitle, keywords, description, release notes, etc.) for every detected locale
- **`/appstore preview`** — Generates a self-contained HTML dashboard showing all metadata, screenshots, character counts, and validation warnings
- **`/appstore screenshots`** — Runs your screenshot pipeline (capture, compose, export)
- **`/appstore upload`** — Uploads everything to App Store Connect via fastlane
- **`/appstore full`** — Runs the entire pipeline end-to-end with a review step before upload

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [fastlane](https://fastlane.tools) set up with `fastlane/metadata/` directory
- At least one locale directory in `fastlane/metadata/` (e.g., `en-US/`)
- Python 3.9+ (stdlib only — no pip dependencies)

## Install

**One-line install** (run from your project root):

```bash
curl -fsSL https://raw.githubusercontent.com/mikwiseman/appstore-skill/main/install.sh | bash
```

**Manual install:**

```bash
mkdir -p .claude/commands scripts

curl -fsSL https://raw.githubusercontent.com/mikwiseman/appstore-skill/main/.claude/commands/appstore.md \
  -o .claude/commands/appstore.md

curl -fsSL https://raw.githubusercontent.com/mikwiseman/appstore-skill/main/scripts/preview_appstore.py \
  -o scripts/preview_appstore.py

chmod +x scripts/preview_appstore.py
```

## Usage

In Claude Code, type:

```
/appstore preview
```

The preview script auto-detects:
- **Locales** from `fastlane/metadata/` subdirectories
- **App name** from the first locale's `name.txt` (falls back to directory name)
- **App icon** by searching for `AppIcon.appiconset/AppIcon*.png`

You can also run the preview script directly:

```bash
python3 scripts/preview_appstore.py           # generates + opens in browser
python3 scripts/preview_appstore.py --no-open  # generates without opening
```

## Expected project structure

```
your-app/
  fastlane/
    metadata/
      en-US/           # at least one locale
        name.txt
        subtitle.txt
        keywords.txt
        description.txt
        ...
      ja/              # additional locales auto-detected
      de-DE/
    screenshots/
      en-US/           # optional — shown in preview
      ja/
    Appfile            # optional — used for bundle ID detection
    Fastfile           # optional — used for upload
  *.xcodeproj/         # optional — used for scheme detection
```

## License

MIT
