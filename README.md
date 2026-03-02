# appstore-skill

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that takes you from **zero to App Store** — no fastlane setup required.

Point it at any iOS project and it generates the full `fastlane/` structure, writes metadata (with Exa SEO research), creates screenshots (Gemini Nano Banana 2 + Playwright), builds an HTML preview, and uploads to App Store Connect.

## Modes

| Mode | What it does |
|------|-------------|
| `/appstore` | Full pipeline — zero to App Store |
| `/appstore setup` | Create `fastlane/` directory structure from scratch |
| `/appstore metadata` | Generate metadata with Exa competitor/SEO research |
| `/appstore screenshots` | Simulator capture + AI backgrounds + HTML compose + PNG export |
| `/appstore preview` | HTML preview dashboard with all metadata and screenshots |
| `/appstore upload` | Upload to App Store Connect via fastlane |

## Prerequisites

**Required:**
- macOS with [Xcode](https://developer.apple.com/xcode/) and iOS simulators
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- Python 3.9+

**Optional — each feature degrades gracefully without these:**

| Dependency | Used for | Without it |
|-----------|----------|------------|
| `GEMINI_API_KEY` | AI-generated backgrounds (Nano Banana 2) | CSS gradient backgrounds instead |
| `google-genai` + `Pillow` | Gemini image generation | Auto-installed if needed |
| `playwright` + Chromium | PNG export from HTML compositions | Auto-installed if needed |
| [Exa MCP](https://exa.ai) | Competitor/keyword SEO research | Metadata from codebase analysis only |
| [fastlane](https://fastlane.tools) | Upload to App Store Connect | Generate files locally, upload manually |
| Git | Recent changes for release notes | Skips changelog analysis |

## Install

**Ask Claude Code** (easiest):

> Install the appstore skill from https://github.com/mikwiseman/appstore-skill

**Or one-line shell** (from your project root):

```bash
curl -fsSL https://raw.githubusercontent.com/mikwiseman/appstore-skill/main/install.sh | bash
```

## What it generates

```
your-app/
  fastlane/
    metadata/
      en-US/                    # Per-locale metadata
        name.txt                #   30 chars
        subtitle.txt            #   30 chars
        keywords.txt            #   100 chars
        description.txt         #   4000 chars
        promotional_text.txt    #   170 chars
        release_notes.txt       #   4000 chars
        privacy_url.txt
        support_url.txt
        marketing_url.txt
      ja/                       # Additional locales
      de-DE/
      review_information/       # App Review contact
        first_name.txt
        last_name.txt
        email_address.txt
        phone_number.txt
        notes.txt
      copyright.txt             # Shared metadata
      primary_category.txt
      secondary_category.txt
    screenshots/
      en-US/                    # Final composed PNGs (1290x2796)
        01_plan_framed.png
        02_spending_framed.png
        ...
      ja/
    Appfile                     # Bundle ID
    Fastfile                    # Upload lane
    app_store_rating_config.json
  scripts/
    preview_appstore.py         # HTML dashboard generator
  build/
    appstore_preview.html       # Preview dashboard
    backgrounds/                # Gemini-generated backgrounds
    compositions/               # HTML compositions before export
```

## How it works

### Preflight checks

Every run starts with environment validation:
- Platform (macOS required), Xcode CLI tools, Python version
- Project detection (`.xcodeproj` or `.xcworkspace`, handles CocoaPods)
- Simulator availability (prefers Pro Max, falls back to any iPhone)
- Optional dependency status (Exa, Gemini, fastlane)

The skill reports what's available and proceeds with what it has.

### Auto-detection

The skill detects everything from your project — no configuration needed:
- Xcode scheme from `xcodebuild -list` (handles workspaces, multiple schemes)
- Bundle ID from `project.pbxproj` (resolves build-setting variables via `xcodebuild -showBuildSettings`)
- Latest iPhone Pro Max simulator by UDID (falls back to Pro, then any iPhone)
- App icon from `AppIcon.appiconset/`
- Existing localizations from `.xcstrings`, `.lproj`, `.strings`

### Exa SEO research

When generating metadata, the skill uses [Exa MCP](https://exa.ai) to research:
- Competitor apps in your category
- High-volume App Store search keywords
- Metadata writing best practices

If Exa MCP is not configured, metadata is generated from codebase analysis alone.

### Nano Banana 2 screenshots

The screenshot pipeline uses Google's [Nano Banana 2](https://deepmind.google/blog/nano-banana-2-combining-pro-capabilities-with-lightning-fast-speed/) (`gemini-3.1-flash-image-preview`) to generate unique abstract backgrounds for each screen, then composes them with device frames and marketing copy via Playwright.

If `GEMINI_API_KEY` is not available, the skill uses dark CSS gradient backgrounds instead — no API required.

### iOS simulator best practices

The skill follows battle-tested simulator automation patterns:
- UDID-based device selection (not names — avoids ambiguity across runtimes)
- Boot once, reuse across all captures
- Deep links / URL schemes for screen navigation
- Dark mode set before app launch (not after)
- Deterministic waits with retry on blank screenshots
- Clean state between locale switches
- Shutdown after pipeline completes

### Edge case handling

The skill handles common failure scenarios:
- **Build failures**: Shows errors, stops before attempting screenshot capture
- **App crashes**: Detects launch failures, suggests debugging in Xcode
- **Blank screenshots**: Retries with longer waits (up to 3 attempts)
- **Missing dependencies**: Auto-installs Python packages, downloads preview script
- **Gemini errors**: Falls back to CSS gradient backgrounds
- **Exa unavailable**: Proceeds with codebase-only metadata
- **No fastlane CLI**: Generates all files locally for manual upload
- **Existing fastlane/**: Idempotent setup — never overwrites existing files
- **Multiple Xcode projects/schemes**: Asks the user which to use
- **No simulators**: Clear error with instructions to install runtimes

## Preview dashboard

The HTML preview is a self-contained dark-themed dashboard with:
- Pure CSS locale tabs (no JavaScript)
- All metadata fields with character count validation
- Keywords as pill badges
- Screenshot gallery with horizontal scroll
- Age rating grid
- Review information
- Warning banners for missing files

Run it standalone:

```bash
python3 scripts/preview_appstore.py           # generates + opens in browser
python3 scripts/preview_appstore.py --no-open  # generates without opening
```

## License

MIT
