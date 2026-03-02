---
description: Zero to App Store — generates fastlane structure, metadata (with Exa SEO research), screenshots (Gemini + Playwright), HTML preview, and upload.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, mcp__exa__web_search_exa, mcp__exa__get_code_context_exa
argument-hint: [full|setup|metadata|screenshots|preview|upload]
---

# App Store Pipeline — Zero to App Store

You are running the App Store pipeline. This skill takes a developer from **zero** (just an iOS project) to a fully published App Store listing: fastlane structure, metadata, screenshots, preview, and upload.

## ARGUMENTS

The user can pass an optional mode:

- **full** (default, or no argument): Run the entire pipeline end-to-end
- **setup**: Create the `fastlane/` directory structure from scratch
- **metadata**: Generate/refresh all metadata files (with Exa SEO research)
- **screenshots**: Full screenshot pipeline (capture, AI backgrounds, compose, export)
- **preview**: Generate the HTML preview dashboard
- **upload**: Upload to App Store Connect via fastlane

Requested mode: `$ARGUMENTS`

If no argument was given or argument is empty, run **full** pipeline.

---

## PROJECT AUTO-DETECTION

Before running any mode, detect the project context automatically. This works **without** an existing `fastlane/` directory.

### Xcode Scheme
```bash
xcodebuild -list -json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['project']['schemes'][0])"
```

### Bundle ID
Parse `*.xcodeproj/project.pbxproj` for `PRODUCT_BUNDLE_IDENTIFIER`:
```bash
grep -m1 'PRODUCT_BUNDLE_IDENTIFIER' *.xcodeproj/project.pbxproj | sed 's/.*= *"\{0,1\}\([^";]*\)"\{0,1\};.*/\1/'
```

### Simulator (UDID-based — see Simulator Best Practices below)
Get the latest available iPhone Pro Max simulator and extract its UDID:
```bash
xcrun simctl list devices available -j | python3 -c "
import sys, json
data = json.load(sys.stdin)['devices']
sims = [(d['udid'], d['name']) for r in data for d in data[r] if 'Pro Max' in d['name'] and d['isAvailable']]
if sims: print(f'{sims[-1][0]}|{sims[-1][1]}')
else:
    sims = [(d['udid'], d['name']) for r in data for d in data[r] if 'iPhone' in d['name'] and d['isAvailable']]
    if sims: print(f'{sims[-1][0]}|{sims[-1][1]}')
"
```
Store both the UDID and name. **Always use the UDID** in subsequent `simctl` commands.

### App Icon
```bash
find . -path "*/AppIcon.appiconset/AppIcon*.png" -type f 2>/dev/null | head -1
```

### Existing Localizations
Scan for localization files to suggest locales:
```bash
# .xcstrings files
find . -name "*.xcstrings" -not -path "*/.*" 2>/dev/null
# .lproj directories
find . -name "*.lproj" -not -path "*/.*" -type d 2>/dev/null | sed 's/.*\///' | sort -u
# .strings files
find . -name "*.strings" -not -path "*/.*" 2>/dev/null
```

### Existing Fastlane (if present)
If `fastlane/metadata/` exists, scan for locale subdirectories (exclude `review_information` and `trade_representative_contact_information`). If `fastlane/Appfile` exists, read `app_identifier`.

---

## IOS SIMULATOR BEST PRACTICES

These practices ensure reliable, reproducible simulator automation. Follow them in all screenshot and testing workflows.

### 1. Always Use UDIDs, Not Device Names
Device names can be ambiguous (multiple runtimes may have the same name). Always resolve to a UDID first and use it for all subsequent commands:
```bash
# Get UDID once
SIMULATOR_UDID=$(xcrun simctl list devices available -j | python3 -c "
import sys, json
data = json.load(sys.stdin)['devices']
sims = [(d['udid'], d['name']) for r in data for d in data[r] if 'Pro Max' in d['name'] and d['isAvailable']]
print(sims[-1][0] if sims else '')
")

# Use UDID everywhere
xcrun simctl boot "$SIMULATOR_UDID"
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
xcrun simctl io "$SIMULATOR_UDID" screenshot output.png
```

### 2. Boot Once, Reuse Across Captures
Boot the simulator once at the start of the pipeline. Do NOT boot/shutdown between each screenshot:
```bash
xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true  # OK if already booted
# ... capture all screenshots ...
xcrun simctl shutdown "$SIMULATOR_UDID"  # Only at the very end
```

### 3. Use Deep Links for Navigation
Instead of trying to tap through UI, use URL schemes or `xcrun simctl openurl` to navigate directly to specific screens:
```bash
xcrun simctl openurl "$SIMULATOR_UDID" "myapp://tab?name=spending"
```
If the app supports launch arguments for screen navigation, use those:
```bash
xcrun simctl launch "$SIMULATOR_UDID" "com.example.app" --tab spending
```

### 4. Deterministic Waits Instead of Fixed Sleeps
Prefer checking for app readiness rather than `sleep 3`:
```bash
# Wait for app to launch (check process list)
for i in $(seq 1 10); do
    xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null && break
    sleep 0.5
done
# Then wait a bit for UI to render
sleep 2
```
When `sleep` is unavoidable, use 2-3 seconds for initial launch and 1 second between screen transitions.

### 5. Set Appearance Before App Launch
Set dark/light mode before launching the app, not after:
```bash
xcrun simctl ui "$SIMULATOR_UDID" appearance dark
xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID"
```

### 6. Clean State Between Locale Switches
When switching locales, terminate and relaunch the app:
```bash
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -AppleLanguages "($LANG)" -AppleLocale "$LOCALE"
```

### 7. Shutdown After the Pipeline
Always shut down the simulator when done to avoid state leakage:
```bash
xcrun simctl shutdown "$SIMULATOR_UDID" 2>/dev/null || true
```

### 8. Verify Screenshots Immediately
After each capture, verify the file exists and has reasonable dimensions:
```bash
sips -g pixelWidth -g pixelHeight "output.png" 2>/dev/null
```

---

## ASK USER ONCE

Before proceeding with setup or metadata generation, ask the user for:

1. **Locales**: Which locales to generate. Suggest based on detected localizations (e.g., if `.xcstrings` has `ja` and `de`, suggest `en-US`, `ja`, `de-DE`). At minimum, suggest `en-US`.

2. **Contact info for App Review**: First name, last name, email, phone number.

Only ask once — reuse these values across all modes in the pipeline.

---

## MODE: setup

Create the full `fastlane/` directory structure from scratch. This mode is idempotent — it won't overwrite existing files.

### Step 1: Create directory structure

For each locale the user selected:
```
fastlane/
  metadata/
    {locale}/           # e.g., en-US/, ja/, de-DE/
    review_information/
  screenshots/
    {locale}/
  Appfile
  Fastfile
  app_store_rating_config.json
```

### Step 2: Write Appfile
```ruby
app_identifier("{BUNDLE_ID}")  # Auto-detected
```

### Step 3: Write Fastfile
```ruby
default_platform(:ios)

platform :ios do
  desc "Upload metadata, screenshots, and ratings to App Store Connect"
  lane :upload_all do
    deliver(
      skip_binary_upload: true,
      skip_app_version_update: true,
      force: true,
      precheck_include_in_app_purchases: false,
      submission_information: {
        add_id_info_uses_idfa: false
      }
    )
  end
end
```

### Step 4: Write empty metadata stubs

For each locale, create empty files:
- `name.txt`, `subtitle.txt`, `keywords.txt`, `description.txt`, `promotional_text.txt`, `release_notes.txt`
- `privacy_url.txt`, `support_url.txt`, `marketing_url.txt`

For `review_information/`:
- `first_name.txt`, `last_name.txt`, `email_address.txt`, `phone_number.txt`, `notes.txt`
- Pre-fill with the contact info the user provided.

Shared files:
- `copyright.txt` (e.g., "2026 CompanyName")
- `primary_category.txt` (empty)
- `secondary_category.txt` (empty)

### Step 5: Write default age rating config

Write `fastlane/app_store_rating_config.json`:
```json
{
  "CARTOON_FANTASY_VIOLENCE": 0,
  "REALISTIC_VIOLENCE": 0,
  "PROLONGED_GRAPHIC_SADISTIC_REALISTIC_VIOLENCE": 0,
  "PROFANITY_CRUDE_HUMOR": 0,
  "MATURE_SUGGESTIVE": 0,
  "HORROR": 0,
  "MEDICAL_TREATMENT_INFO": 0,
  "ALCOHOL_TOBACCO_DRUGS": 0,
  "GAMBLING": 0,
  "SEXUAL_CONTENT_NUDITY": 0,
  "GRAPHIC_SEXUAL_CONTENT_NUDITY": 0,
  "UNRESTRICTED_WEB_ACCESS": 0,
  "GAMBLING_CONTESTS": 0
}
```

### Step 6: Confirm

List all created files and directories. Tell the user the setup is complete.

---

## MODE: metadata

Generate or refresh ALL App Store metadata files by analyzing the current codebase and researching competitors/SEO via Exa.

### Step 1: Read the codebase

Read these files to understand the current state of the app:

1. **Features & UI**: Read all SwiftUI views — understand what screens exist, what they do, what the user experience is
2. **Localizations**: Read localization files (`.xcstrings`, `.strings`, `.lproj`) — understand all user-facing strings
3. **Data models**: Read data models — understand the data architecture
4. **Recent changes**: Run `git log --oneline -20` to understand recent development
5. **Existing metadata**: Read all files in `fastlane/metadata/` to understand what currently exists

### Step 2: Exa research

Use Exa MCP tools to research competitors and SEO keywords. First get the current date:
```bash
date "+%Y-%m-%d %B %Y"
```

Then run these searches:
1. **Competitors**: `mcp__exa__web_search_exa("best [app category] apps iOS App Store [MONTH] [YEAR]")` — understand the competitive landscape
2. **ASO keywords**: `mcp__exa__web_search_exa("[app category] app store optimization keywords [MONTH] [YEAR]")` — find high-volume search terms
3. **Writing patterns**: `mcp__exa__get_code_context_exa("app store metadata best practices description keywords")` — learn effective metadata writing patterns

Use these insights to write better keywords, descriptions, and subtitles that compete effectively.

### Step 3: Write metadata files

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
- **SEO keywords**: Use insights from Exa research. Include high-volume terms relevant to the app's category.
- **release_notes.txt**: Summarize what's new based on recent git history. If this is an initial release, write first-release notes.

### Step 4: Show summary

Show the user a summary of all generated metadata — app name, subtitle, keywords, description length, etc. Ask for approval before proceeding.

---

## MODE: screenshots

Run the full screenshot pipeline: capture from simulator, generate AI backgrounds with Gemini Nano Banana 2, compose HTML, and export final PNGs.

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

If `GEMINI_API_KEY` is not set, ask the user to provide it (needed for Gemini Nano Banana 2 image generation).

If Python deps are missing, install them:
```bash
pip3 install google-genai playwright
python3 -m playwright install chromium
```

### Step 2: Analyze the app's screens

Read the app's SwiftUI views to identify the **main screens** that should be showcased in App Store screenshots. Typically 3-5 screens that highlight core features.

For each screen, determine:
- A short identifier (e.g., `01_plan`, `02_spending`)
- Which tab or navigation path leads to it (prefer URL schemes / deep links)
- Marketing title and subtitle for each locale

Ask the user to confirm the screen list and marketing copy before proceeding.

### Step 3: Capture raw screenshots from simulator

Follow the **iOS Simulator Best Practices** section above. Key workflow:

```bash
# 1. Get simulator UDID (from auto-detection)
SIMULATOR_UDID="<detected-udid>"

# 2. Boot once
xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true

# 3. Build the app
xcodebuild build -scheme "<SCHEME>" \
    -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
    -derivedDataPath build/screenshots -quiet 2>&1 | tail -5

# 4. Find and install the app
APP_PATH=$(find build/screenshots -name "*.app" -path "*/Debug-iphonesimulator/*" | head -1)
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"

# 5. Set dark mode BEFORE launching
xcrun simctl ui "$SIMULATOR_UDID" appearance dark

# 6. For each locale:
for LOCALE in en-US ja de-DE; do
    # Map locale to language code
    LANG_CODE="${LOCALE%%-*}"  # en, ja, de

    # For each screen:
    for SCREEN in 01_plan 02_spending 03_detail; do
        # Terminate previous instance
        xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true

        # Launch with locale
        xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" \
            -AppleLanguages "($LANG_CODE)" -AppleLocale "$LOCALE"

        # Navigate to screen (via deep link if supported)
        # xcrun simctl openurl "$SIMULATOR_UDID" "myapp://screen/$SCREEN"

        # Wait for UI to render
        sleep 2

        # Capture
        mkdir -p "fastlane/screenshots/$LOCALE"
        xcrun simctl io "$SIMULATOR_UDID" screenshot \
            "fastlane/screenshots/$LOCALE/${SCREEN}.png"

        # Verify capture
        sips -g pixelWidth -g pixelHeight \
            "fastlane/screenshots/$LOCALE/${SCREEN}.png" 2>/dev/null
    done
done

# 7. Shutdown when done
xcrun simctl shutdown "$SIMULATOR_UDID" 2>/dev/null || true
```

If the app doesn't support deep links or launch arguments for navigation, tell the user which screens need to be navigated to manually, or explore SwiftUI views for `TabView` / `NavigationStack` patterns to determine how to reach each screen.

### Step 4: Generate AI backgrounds with Gemini Nano Banana 2

Use the **Nano Banana 2** model (`gemini-3.1-flash-image-preview`) for background generation:

```python
from google import genai
from google.genai import types
import os

client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

# Each screen gets a distinct color theme
color_themes = {
    "01_plan": "deep teal and dark cyan",
    "02_spending": "warm amber and dark bronze",
    "03_detail": "muted purple and dark violet",
    "04_stats": "forest green and dark emerald",
    "05_settings": "slate blue and dark navy",
}

for screen, colors in color_themes.items():
    response = client.models.generate_content(
        model="gemini-3.1-flash-image-preview",
        contents=(
            f"Create a 1290x2796 abstract background image. "
            f"Dark background with {colors} tones. "
            f"Minimal geometric design with subtle shapes and gradients. "
            f"Very clean, modern aesthetic. No text, no objects, no people. "
            f"Suitable as a phone wallpaper background behind a device mockup."
        ),
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"],
        ),
    )

    for part in response.parts:
        if part.inline_data is not None:
            image = part.as_image()
            image.save(f"build/backgrounds/{screen}_bg.png")
```

Then upscale to exact target size:
```bash
mkdir -p build/backgrounds
sips -z 2796 1290 build/backgrounds/*_bg.png
```

### Step 5: Compose HTML pages

For each locale and screen, generate an HTML composition at 1x scale (430x932 CSS pixels = 1290x2796 at 3x):

- Full-bleed AI background image
- Marketing title + subtitle at the top (white text with subtle shadow)
- Device frame with the raw screenshot (rounded corners, shadow, ~68% of page height)
- All images embedded as base64 data URIs for self-contained HTML

Save to `build/compositions/{locale}/{screen}.html`.

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

Save final screenshots to `fastlane/screenshots/{locale}/{screen}_framed.png`.

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

First verify fastlane is configured:
```bash
test -f fastlane/Appfile && test -f fastlane/Fastfile && echo "fastlane OK" || echo "Run /appstore setup first"
```

Then upload:
```bash
fastlane ios upload_all
```

This uploads metadata, screenshots, categories, and age rating. Uses App Store Connect API key authentication configured in the Fastfile.

Verify: Check output for "fastlane.tools finished successfully".

---

## MODE: full

Run the complete pipeline in order. This is the **zero to App Store** flow.

### 1. Setup

Check if `fastlane/` exists. If not, run the **setup** mode to create the full directory structure. Ask the user for locales and contact info.

### 2. Metadata

Run the **metadata** mode. Read the codebase, research via Exa, generate all metadata files. Show summary and ask for approval.

### 3. Screenshots

Run the full **screenshots** pipeline (capture → Nano Banana 2 backgrounds → compose → export).

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
