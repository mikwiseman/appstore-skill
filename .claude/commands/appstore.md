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

Run the full screenshot pipeline: capture from simulator, generate AI backgrounds, compose HTML, and export final PNGs.

**Target size**: 1290x2796 (iPhone Pro Max 6.7" App Store requirement)

### Step 1: Prerequisites

```bash
# Check GEMINI_API_KEY
echo "GEMINI_API_KEY: ${GEMINI_API_KEY:+SET}"

# Check Python deps
python3 -c "from google import genai; from playwright.sync_api import sync_playwright; print('deps OK')" 2>&1

# Check Playwright browsers
python3 -c "from playwright.sync_api import sync_playwright; p = sync_playwright().start(); b = p.chromium.launch(); b.close(); p.stop(); print('playwright OK')" 2>&1
```

If `GEMINI_API_KEY` is not set, ask the user to provide it (needed for AI background generation via Gemini).

If Python deps are missing, install them:
```bash
pip3 install google-genai playwright
python3 -m playwright install chromium
```

### Step 2: Analyze the app's screens

Read the app's SwiftUI views / storyboards to identify the **main screens** that should be showcased in App Store screenshots. Typically 3-5 screens that highlight core features.

For each screen, determine:
- A short identifier (e.g., `01_plan`, `02_spending`)
- Which tab or navigation path leads to it
- Marketing title and subtitle for each locale

Ask the user to confirm the screen list and marketing copy before proceeding.

### Step 3: Capture raw screenshots from simulator

For each locale and each screen:

```bash
# Boot simulator (use auto-detected device)
SIMULATOR_ID=$(xcrun simctl list devices available | grep "<DEVICE>" | head -1 | grep -oE '[A-F0-9-]{36}')
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true

# Build the app
xcodebuild build-for-testing -scheme "<SCHEME>" -destination "platform=iOS Simulator,name=<DEVICE>" -derivedDataPath build/screenshots -quiet

# Install the app
APP_PATH=$(find build/screenshots -name "*.app" -path "*/Debug-iphonesimulator/*" | head -1)
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

# Set dark mode
xcrun simctl ui "$SIMULATOR_ID" appearance dark

# For each locale/screen: launch app, wait for UI, capture
xcrun simctl launch "$SIMULATOR_ID" "<BUNDLE_ID>" -AppleLanguages "(<lang>)" -AppleLocale "<locale>"
sleep 3
xcrun simctl io "$SIMULATOR_ID" screenshot "fastlane/screenshots/<locale>/<screen>.png"
```

If the app supports launch arguments for navigating to specific screens (e.g., `--tab plan`), use them. Otherwise, you may need to navigate manually or ask the user how to reach each screen.

### Step 4: Generate AI backgrounds with Gemini

For each screen, generate a unique abstract background using the Gemini Flash Image API (Nanobanana2):

```python
from google import genai
from google.genai import types

client = genai.Client(api_key=api_key)

response = client.models.generate_content(
    model="gemini-2.0-flash-preview-image-generation",
    contents="Create a 1290x2796 abstract background image. Dark background. "
             "Minimal geometric design with subtle shapes and gradients. "
             "Very clean, modern aesthetic. No text, no objects, no people. "
             "Suitable as a phone wallpaper background behind a device mockup.",
    config=types.GenerateContentConfig(
        response_modalities=["IMAGE", "TEXT"],
    ),
)
```

Each screen should have a distinct color theme (e.g., teal, amber, purple). Save to `build/backgrounds/<screen>_bg.png`.

Then upscale to exact target size:
```bash
sips -z 2796 1290 build/backgrounds/*_bg.png
```

### Step 5: Compose HTML pages

For each locale and screen, generate an HTML composition at 1x scale (430x932 CSS pixels = 1290x2796 at 3x):

- Full-bleed AI background image
- Marketing title + subtitle at the top (white text with subtle shadow)
- Device frame with the raw screenshot (rounded corners, shadow, ~68% of page height)
- All images embedded as base64 data URIs for self-contained HTML

Save to `build/compositions/<locale>/<screen>.html`.

**Key dimensions** (at 1x logical scale):
- Page: 430x932
- Device frame: ~292x634 (maintains iPhone aspect ratio)
- Corner radius: 28px
- Title: 28px bold, subtitle: 15px regular

### Step 6: Export final PNGs with Playwright

Render each HTML composition at 3x device scale to produce 1290x2796 PNGs:

```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch()
    context = browser.new_context(
        viewport={"width": 430, "height": 932},
        device_scale_factor=3,
    )
    page = context.new_page()
    page.goto(f"file://{html_path}", wait_until="networkidle")
    page.wait_for_timeout(500)
    page.screenshot(path=output_path, full_page=False)
```

Save final screenshots to `fastlane/screenshots/<locale>/<screen>_framed.png`.

### Step 7: Verify

```bash
# Check dimensions of exported screenshots
sips -g pixelWidth -g pixelHeight fastlane/screenshots/*/01_*_framed.png
```

Expected: 1290x2796 for each file.

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

Run the full **screenshots** pipeline (capture → AI backgrounds → compose → export).

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
