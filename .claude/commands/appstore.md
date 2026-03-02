---
description: Full App Store pipeline — metadata, screenshots, preview dashboard, and upload to App Store Connect.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
argument-hint: [full|screenshots|metadata|preview|upload]
---

# App Store Pipeline

You are running the App Store pipeline. This handles everything for App Store publication: metadata generation, screenshot creation, visual HTML preview, and upload to App Store Connect.

## ARGUMENTS

The user can pass an optional mode:

- **full** (default, or no argument): Run the entire pipeline end-to-end
- **screenshots**: Only regenerate screenshots (capture, backgrounds, compose, export)
- **metadata**: Only generate/refresh all metadata files
- **preview**: Only generate the HTML preview dashboard
- **upload**: Only upload to App Store Connect via fastlane

Requested mode: `$ARGUMENTS`

If no argument was given or argument is empty, run **full** pipeline.

## PROJECT AUTO-DETECTION

Before running any mode, detect the project context automatically:

### Locales
Scan `fastlane/metadata/` for subdirectories (exclude `review_information` and `trade_representative_contact_information`). Each subdirectory is a locale (e.g., `en-US`, `ja`, `de-DE`).

### App Name
Read `name.txt` from the first detected locale directory.

### Bundle ID
Read from `fastlane/Appfile` — look for `app_identifier` value.

### Xcode Scheme
Run: `xcodebuild -list -json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['project']['schemes'][0])"` — use the first scheme.

### Simulator
Run: `xcrun simctl list devices available -j | python3 -c "import sys,json; ds=json.load(sys.stdin)['devices']; print([d['name'] for r in ds for d in ds[r] if 'iPhone' in d['name'] and d['isAvailable']][-1])"` — use the latest available iPhone simulator.

### Screenshots
Check `fastlane/screenshots/` for existing screenshot PNGs per locale.

### App Icon
Search for `AppIcon.appiconset/AppIcon*.png` via recursive glob from the project root.

---

## MODE: metadata

Generate or refresh ALL App Store metadata files by analyzing the current codebase.

### Step 1: Read the codebase

Read these files to understand the current state of the app:

1. **Features & UI**: Read all SwiftUI views — understand what screens exist, what they do, what the user experience is
2. **Localizations**: Read localization files (`.xcstrings`, `.strings`, `.lproj`) — understand all user-facing strings
3. **Data models**: Read data models — understand the data architecture
4. **Recent changes**: Run `git log --oneline -20` to understand recent development
5. **Existing metadata**: Read all files in `fastlane/metadata/` to understand what currently exists

### Step 2: Write metadata files

Write or update these files with enforced character limits:

**Per-locale files** (`fastlane/metadata/{locale}/`):

| File | Limit | Notes |
|------|-------|-------|
| `name.txt` | 30 chars | App name |
| `subtitle.txt` | 30 chars | Tagline |
| `keywords.txt` | 100 chars | Comma-separated, no spaces after commas |
| `description.txt` | 4000 chars | Full description with features |
| `promotional_text.txt` | 170 chars | Can be updated without new build |
| `release_notes.txt` | 4000 chars | What's new in this version |

**Shared files** (`fastlane/metadata/`):

| File | Notes |
|------|-------|
| `copyright.txt` | e.g., "2026 YourCompany" |
| `primary_category.txt` | e.g., "Finance" |
| `secondary_category.txt` | e.g., "Lifestyle" |

**Review information** (`fastlane/metadata/review_information/`):

| File | Notes |
|------|-------|
| `first_name.txt` | Reviewer contact |
| `last_name.txt` | Reviewer contact |
| `email_address.txt` | Reviewer contact |
| `phone_number.txt` | Reviewer contact |
| `notes.txt` | Instructions for App Review team |

**Age rating** (`fastlane/app_store_rating_config.json`):

Update if app features have changed (gambling, violence, etc.).

### Writing Guidelines

- **Write idiomatic text for each locale** — NOT machine-translated English. Each locale should read as if written natively by a speaker of that language.
- **Character limits are hard limits**: Count characters carefully. For keywords, count the entire string including commas.
- **SEO keywords**: Research App Store search terms relevant to the app's category. Include high-volume terms.
- **release_notes.txt**: Summarize what's new based on recent git history. If this is an initial release, write first-release notes.

---

## MODE: screenshots

Run the full screenshot pipeline: capture, AI backgrounds, composition, and export.

### Prerequisites Check

```bash
# 1. Check if screenshot scripts exist
ls scripts/capture_screenshots.sh scripts/generate_backgrounds.py scripts/compose_screenshots.py scripts/export_screenshots.py 2>/dev/null

# 2. Check Python dependencies for any scripts that exist
python3 -c "from playwright.sync_api import sync_playwright; print('playwright OK')" 2>/dev/null
```

If screenshot scripts don't exist, tell the user that the screenshot pipeline needs to be set up first.

### Steps

1. **Capture raw screenshots** using the detected simulator
2. **Generate backgrounds** (if background generation script exists)
3. **Compose HTML pages** (if composition script exists)
4. **Export final PNGs** (if export script exists)

Adapt the steps to whatever screenshot scripts exist in the project.

---

## MODE: preview

Generate the HTML preview dashboard showing all metadata and screenshots.

```bash
python3 scripts/preview_appstore.py
```

This generates `build/appstore_preview.html` — a self-contained dark-themed dashboard with:
- Locale tabs (pure CSS, no JS)
- All metadata fields with character count validation
- Keywords as pill badges
- Screenshot gallery with horizontal scroll
- Age rating grid
- Review information
- Warning banner for missing files

The file auto-opens in the browser. Use `--no-open` to skip.

---

## MODE: upload

Upload everything to App Store Connect via fastlane.

```bash
fastlane ios upload_all
```

This uploads metadata, screenshots, categories, and age rating. Uses App Store Connect API key authentication configured in the Fastfile.

Verify: Check output for "fastlane.tools finished successfully".

---

## MODE: full

Run the complete pipeline in order:

### 1. Prerequisites

Auto-detect project context (locales, app name, bundle ID, etc.).

### 2. Metadata

Check if metadata files exist and look current. If any are missing or stale, run the **metadata** mode to generate/refresh them. Tell the user what was updated.

### 3. Screenshots

Run the full **screenshots** pipeline if screenshot scripts exist. Otherwise, skip and inform the user.

### 4. Preview

Run the **preview** mode to generate the HTML dashboard. The preview opens in the browser automatically.

**PAUSE HERE.** Tell the user:

> The App Store preview is open in your browser. Review the metadata and screenshots.
> When you're satisfied, say **"upload"** to push everything to App Store Connect.
> Or tell me what to change.

Wait for user confirmation before proceeding to upload.

### 5. Upload

After user confirms, run the **upload** mode.

### 6. Summary

Show a completion summary:

```
App Store Pipeline Complete!

Metadata: [updated/unchanged]
Screenshots: [list per locale, or "skipped"]
Preview: build/appstore_preview.html
Upload: [success/skipped]
```

---

## EXECUTION

Now execute the requested mode. Follow the steps in order. After each step, verify the output before proceeding.

If any step fails:
1. Show the full error message
2. Diagnose the root cause
3. Fix the issue
4. Retry the step
