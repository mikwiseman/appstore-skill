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

## PREFLIGHT CHECKS

Run these checks **before every mode** to understand what's available. Report results to the user as a status summary, then proceed with what's available.

### 1. Platform check

```bash
uname -s
```
If not `Darwin`, stop and tell the user: "This skill requires macOS with Xcode. It cannot run on Linux or Windows."

### 2. Xcode check

```bash
xcode-select -p 2>/dev/null && echo "xcode OK" || echo "xcode MISSING"
```
If missing, tell the user: "Install Xcode Command Line Tools: `xcode-select --install`"

### 3. Python check

```bash
python3 --version 2>/dev/null
```
If missing or below 3.9, tell the user to install Python 3.9+.

### 4. Project detection

Try to find an Xcode project or workspace:
```bash
# Check for .xcodeproj
ls -d *.xcodeproj 2>/dev/null | head -1

# If no .xcodeproj, check for .xcworkspace (CocoaPods / SPM workspace)
ls -d *.xcworkspace 2>/dev/null | head -1
```

**Edge case — multiple projects:** If more than one `.xcodeproj` exists, ask the user which one to use.

**Edge case — workspace only:** If only `.xcworkspace` exists (common with CocoaPods), use `-workspace` flag instead of `-project` in all `xcodebuild` commands:
```bash
# With .xcodeproj:
xcodebuild -list -json 2>/dev/null

# With .xcworkspace:
xcodebuild -workspace "*.xcworkspace" -list -json 2>/dev/null
```

**Edge case — no project at all:** If neither exists, tell the user: "No Xcode project found. Run this from the root of an iOS project directory."

### 5. Git check

```bash
git rev-parse --is-inside-work-tree 2>/dev/null && echo "git OK" || echo "git MISSING"
```
If Git is not initialized, skip `git log` in metadata mode. Not a blocker.

### 6. Exa MCP availability

Try to determine if Exa MCP tools are available. **Do not try to call them during preflight** — just note availability based on whether you have access to `mcp__exa__web_search_exa` in your tool list.

If Exa is NOT available:
- Metadata mode still works — skip the Exa research step and write metadata based on codebase analysis alone.
- Tell the user: "Exa MCP not configured — skipping competitor/SEO research. Metadata will be based on codebase analysis. For better results, configure Exa MCP (https://exa.ai)."

### 7. Mode-specific checks

**For `screenshots` mode**, also check:
```bash
# GEMINI_API_KEY
echo "GEMINI_API_KEY: ${GEMINI_API_KEY:+SET}"

# google-genai + Pillow (both needed for image generation)
python3 -c "from google import genai; from PIL import Image; print('genai+pil OK')" 2>&1

# Playwright + Chromium
python3 -c "from playwright.sync_api import sync_playwright; p = sync_playwright().start(); b = p.chromium.launch(); b.close(); p.stop(); print('playwright OK')" 2>&1
```

- **No `GEMINI_API_KEY`**: Ask user to provide it. If they can't, offer to skip AI backgrounds and use solid dark gradient backgrounds instead (CSS-only, no Gemini needed).
- **No `google-genai`**: `pip3 install google-genai`
- **No `Pillow`**: `pip3 install Pillow` (needed for `part.as_image()` — Gemini SDK uses PIL internally)
- **No `playwright`**: `pip3 install playwright && python3 -m playwright install chromium`
- **Playwright installed but no Chromium**: `python3 -m playwright install chromium`

**For `upload` mode**, also check:
```bash
which fastlane 2>/dev/null && echo "fastlane OK" || echo "fastlane MISSING"
```
If fastlane is not installed, tell the user: "Install fastlane: `gem install fastlane` or `brew install fastlane`"

**For `preview` mode**, also check:
```bash
test -f scripts/preview_appstore.py && echo "preview script OK" || echo "preview script MISSING"
```
If missing, download it:
```bash
mkdir -p scripts
curl -fsSL "https://raw.githubusercontent.com/mikwiseman/appstore-skill/main/scripts/preview_appstore.py" -o scripts/preview_appstore.py
chmod +x scripts/preview_appstore.py
```

### Preflight summary

After all checks, show a brief status report:
```
Preflight:
  Platform: macOS ✓
  Xcode: [version] ✓
  Python: [version] ✓
  Project: [name].xcodeproj ✓
  Git: ✓
  Exa MCP: [available/not configured]
  Gemini: [API key set/not set]
  Fastlane: [installed/not installed]
```

Then proceed with the requested mode.

---

## PROJECT AUTO-DETECTION

After preflight, detect project context automatically. This works **without** an existing `fastlane/` directory.

### Xcode Scheme

```bash
# For .xcodeproj:
xcodebuild -list -json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); schemes=d.get('project',d.get('workspace',{})).get('schemes',[]); print(schemes[0] if schemes else '')"

# For .xcworkspace:
xcodebuild -workspace "*.xcworkspace" -list -json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); schemes=d.get('project',d.get('workspace',{})).get('schemes',[]); print(schemes[0] if schemes else '')"
```

**Edge case — multiple schemes:** If there are multiple schemes, list them and ask the user which one to use. Filter out test schemes (names ending in `Tests`, `UITests`).

**Edge case — no schemes:** If `xcodebuild -list` returns no schemes, tell the user: "No Xcode schemes found. Open the project in Xcode and verify a scheme exists."

### Bundle ID

Parse `*.xcodeproj/project.pbxproj` for `PRODUCT_BUNDLE_IDENTIFIER`:
```bash
grep 'PRODUCT_BUNDLE_IDENTIFIER' *.xcodeproj/project.pbxproj | grep -v '//' | sed 's/.*= *"\{0,1\}\([^";]*\)"\{0,1\};.*/\1/' | sort -u | head -1
```

**Edge case — variable references:** If the result contains `$(` (e.g., `$(PRODUCT_BUNDLE_IDENTIFIER:default)`, `$(BASE_BUNDLE_IDENTIFIER).dev`), try to resolve it:
```bash
# Try xcodebuild to resolve the actual value
xcodebuild -scheme "<SCHEME>" -showBuildSettings 2>/dev/null | grep 'PRODUCT_BUNDLE_IDENTIFIER' | awk '{print $3}'
```
If it still can't be resolved, ask the user for their bundle ID.

**Edge case — no bundle ID found:** Ask the user to provide it manually.

### Simulator (UDID-based — see Simulator Best Practices below)

Get the latest available iPhone Pro Max simulator and extract its UDID:
```bash
xcrun simctl list devices available -j | python3 -c "
import sys, json
data = json.load(sys.stdin)['devices']
# Prefer Pro Max for 6.7\" screenshots
sims = [(d['udid'], d['name']) for r in data for d in data[r] if 'Pro Max' in d['name'] and d['isAvailable']]
if sims:
    print(f'{sims[-1][0]}|{sims[-1][1]}')
else:
    # Fall back to any Pro model
    sims = [(d['udid'], d['name']) for r in data for d in data[r] if 'Pro' in d['name'] and 'iPhone' in d['name'] and d['isAvailable']]
    if sims:
        print(f'{sims[-1][0]}|{sims[-1][1]}')
    else:
        # Fall back to any iPhone
        sims = [(d['udid'], d['name']) for r in data for d in data[r] if 'iPhone' in d['name'] and d['isAvailable']]
        if sims:
            print(f'{sims[-1][0]}|{sims[-1][1]}')
        else:
            print('NONE')
"
```
Store both the UDID and name. **Always use the UDID** in subsequent `simctl` commands.

**Edge case — no simulators at all:** Tell the user: "No iPhone simulators found. Open Xcode > Settings > Components and download an iOS simulator runtime."

**Edge case — no Pro Max simulator:** A non-Pro Max simulator works fine but produces screenshots at a different resolution. Tell the user which simulator is being used and that screenshots may need resizing for App Store submission (target is 1290x2796 for 6.7").

### App Icon
```bash
find . -path "*/AppIcon.appiconset/AppIcon*.png" -type f 2>/dev/null | head -1
```

**Edge case — no app icon found:** Not a blocker. The preview dashboard will show without an icon. Tell the user: "No app icon found — preview will render without it."

### Existing Localizations

Scan for localization files to suggest locales:
```bash
# .xcstrings files — extract language codes from JSON keys
find . -name "*.xcstrings" -not -path "*/.*" 2>/dev/null | head -1 | xargs python3 -c "
import sys, json
if sys.argv[1:]:
    data = json.load(open(sys.argv[1]))
    langs = set()
    for s in data.get('strings', {}).values():
        langs.update(s.get('localizations', {}).keys())
    print(' '.join(sorted(langs)))
" 2>/dev/null

# .lproj directories
find . -name "*.lproj" -not -path "*/.*" -type d 2>/dev/null | sed 's/.*\///' | sed 's/\.lproj$//' | sort -u
```

**Edge case — no localizations found:** Suggest `en-US` as the only locale. The user can add more later.

### Existing Fastlane (if present)

If `fastlane/metadata/` exists, scan for locale subdirectories (exclude `review_information` and `trade_representative_contact_information`). If `fastlane/Appfile` exists, read `app_identifier` — this overrides the bundle ID from pbxproj.

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

**Edge case — no deep links:** If the app doesn't register any URL scheme (check `Info.plist` for `CFBundleURLSchemes`), you have two options:
1. Launch the app and tell the user to manually navigate to each screen, then trigger the screenshot capture.
2. Explore the SwiftUI views for `TabView` / `NavigationStack` patterns and add launch arguments to the app (requires code changes — ask the user first).

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
**Edge case — blank screenshot:** If `pixelWidth` and `pixelHeight` are suspiciously small (< 100px) or the file size is < 10KB, the app likely hasn't rendered yet. Wait longer and retry (up to 3 attempts with 2-second intervals).

### 9. Handle Simulator Boot Failure
```bash
xcrun simctl boot "$SIMULATOR_UDID" 2>&1
```
If boot fails with "Unable to boot device in current state: Booted", the simulator is already running — that's fine, continue.
If boot fails with other errors, try:
1. `xcrun simctl shutdown "$SIMULATOR_UDID" 2>/dev/null; sleep 1; xcrun simctl boot "$SIMULATOR_UDID"`
2. If that fails: "Simulator failed to boot. Try opening Simulator.app manually and booting the device."

---

## ASK USER ONCE

Before proceeding with setup or metadata generation, ask the user for:

1. **Locales**: Which locales to generate. Suggest based on detected localizations (e.g., if `.xcstrings` has `ja` and `de`, suggest `en-US`, `ja`, `de-DE`). If no localizations were detected, suggest `en-US` only. At minimum, always include `en-US`.

2. **Contact info for App Review**: First name, last name, email, phone number. If `fastlane/metadata/review_information/` already has this data, show it and ask if it's still correct.

Only ask once — reuse these values across all modes in the pipeline.

---

## MODE: setup

Create the full `fastlane/` directory structure from scratch. This mode is **idempotent** — it creates missing files/directories but does NOT overwrite existing ones.

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

Use `mkdir -p` for directories. For files, check if they exist before writing:
```bash
# Example — only write if file doesn't exist:
test -f fastlane/Appfile || echo 'app_identifier("com.example.app")' > fastlane/Appfile
```

### Step 2: Write Appfile
```ruby
app_identifier("{BUNDLE_ID}")  # Auto-detected
```
**Edge case — bundle ID not detected:** If auto-detection failed and the user provided the bundle ID, use that. If neither is available, write a placeholder and tell the user to fill it in: `app_identifier("YOUR_BUNDLE_ID_HERE")`.

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

For each locale, create empty files (only if they don't already exist):
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

Write `fastlane/app_store_rating_config.json` (only if it doesn't exist):
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

**Edge case — `fastlane/` already fully set up:** If all files already exist, tell the user: "Fastlane structure already exists. No changes made. Run `/appstore metadata` to refresh metadata content."

---

## MODE: metadata

Generate or refresh ALL App Store metadata files by analyzing the current codebase and (optionally) researching competitors/SEO via Exa.

### Prerequisite check
Verify `fastlane/metadata/` exists with at least one locale directory. If not, tell the user: "No fastlane metadata structure found. Run `/appstore setup` first." and stop.

### Step 1: Read the codebase

Read these files to understand the current state of the app:

1. **Features & UI**: Read all SwiftUI views — understand what screens exist, what they do, what the user experience is
2. **Localizations**: Read localization files (`.xcstrings`, `.strings`, `.lproj`) — understand all user-facing strings
3. **Data models**: Read data models — understand the data architecture
4. **Recent changes**: Run `git log --oneline -20` to understand recent development (**skip if Git not available** — just note "Git not available, skipping recent changes analysis")
5. **Existing metadata**: Read all files in `fastlane/metadata/` to understand what currently exists

### Step 2: Exa research (if available)

**If Exa MCP is available**, use it to research competitors and SEO keywords. First get the current date:
```bash
date "+%Y-%m-%d %B %Y"
```

Then run these searches:
1. **Competitors**: `mcp__exa__web_search_exa("best [app category] apps iOS App Store [MONTH] [YEAR]")` — understand the competitive landscape
2. **ASO keywords**: `mcp__exa__web_search_exa("[app category] app store optimization keywords [MONTH] [YEAR]")` — find high-volume search terms
3. **Writing patterns**: `mcp__exa__get_code_context_exa("app store metadata best practices description keywords")` — learn effective metadata writing patterns

Use these insights to write better keywords, descriptions, and subtitles that compete effectively.

**If Exa MCP is NOT available**, skip this step entirely. Write metadata based solely on codebase analysis. Tell the user: "Exa MCP not available — writing metadata from codebase analysis only. For SEO-optimized metadata, configure Exa MCP and re-run `/appstore metadata`."

**Edge case — Exa errors:** If an Exa call fails (rate limit, API error, empty results), log the error and continue without that data. Do not let Exa failures block metadata generation.

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
- **SEO keywords**: If Exa research was done, use those insights. Otherwise, choose keywords based on app functionality.
- **release_notes.txt**: Summarize what's new based on recent git history. If Git is unavailable or this is an initial release, write first-release notes.

### Step 4: Show summary

Show the user a summary of all generated metadata — app name, subtitle, keywords, description length, character counts for each field. Highlight any fields that are close to or over their character limit. Ask for approval before proceeding.

---

## MODE: screenshots

Run the full screenshot pipeline: capture from simulator, generate AI backgrounds with Gemini Nano Banana 2, compose HTML, and export final PNGs.

**Target size**: 1290x2796 (iPhone Pro Max 6.7" App Store requirement)

### Step 1: Prerequisites

Run the mode-specific preflight checks from the PREFLIGHT CHECKS section. Specifically verify:

1. **Simulator available** — if no simulator was detected, stop.
2. **GEMINI_API_KEY** — if not set, ask the user. If they can't provide it, offer the **solid background alternative** (see below).
3. **Python dependencies** — `google-genai`, `Pillow`, `playwright` + Chromium.

**Solid background alternative (no Gemini):**
If the user cannot provide a Gemini API key, generate screenshots with CSS gradient backgrounds instead of AI-generated backgrounds. Use distinct dark gradients per screen:
```css
/* Example gradient themes per screen */
background: linear-gradient(160deg, #0a2e2e 0%, #051a1a 50%, #000000 100%); /* teal */
background: linear-gradient(160deg, #2e1a0a 0%, #1a0f05 50%, #000000 100%); /* amber */
background: linear-gradient(160deg, #1a0a2e 0%, #0f051a 50%, #000000 100%); /* purple */
```
This produces acceptable screenshots without any API cost. Tell the user: "Using CSS gradient backgrounds. For AI-generated backgrounds, set `GEMINI_API_KEY` and re-run."

### Step 2: Analyze the app's screens

Read the app's SwiftUI views to identify the **main screens** that should be showcased in App Store screenshots. Typically 3-5 screens that highlight core features.

Look for:
- `TabView` — each tab is likely a showcase screen
- `NavigationStack` / `NavigationView` — main views in the navigation hierarchy
- Views with the most UI complexity / user-facing features

For each screen, determine:
- A short identifier (e.g., `01_plan`, `02_spending`)
- Which tab or navigation path leads to it (prefer URL schemes / deep links)
- Marketing title and subtitle for each locale

**Edge case — can't identify screens:** If the code structure is unclear, ask the user: "I found these views: [list]. Which 3-5 should be showcased, and how do I navigate to each one?"

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
```

**Edge case — build fails:** If `xcodebuild build` returns a non-zero exit code:
1. Show the last 20 lines of build output
2. Tell the user: "Build failed. Fix the compilation errors and re-run `/appstore screenshots`."
3. Do NOT proceed to screenshot capture.

```bash
# 4. Find and install the app
APP_PATH=$(find build/screenshots -name "*.app" -path "*/Debug-iphonesimulator/*" | head -1)
```

**Edge case — no .app found:** If `APP_PATH` is empty:
1. Check if the build output is in a different configuration: `find build/screenshots -name "*.app" | head -5`
2. If still nothing: "Build succeeded but no .app was produced. Check the scheme's build settings."

```bash
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

        # Verify capture — retry if blank
        FILE_SIZE=$(stat -f%z "fastlane/screenshots/$LOCALE/${SCREEN}.png" 2>/dev/null || echo "0")
        if [ "$FILE_SIZE" -lt 10000 ]; then
            echo "Screenshot may be blank (${FILE_SIZE} bytes), retrying..."
            sleep 3
            xcrun simctl io "$SIMULATOR_UDID" screenshot \
                "fastlane/screenshots/$LOCALE/${SCREEN}.png"
        fi

        sips -g pixelWidth -g pixelHeight \
            "fastlane/screenshots/$LOCALE/${SCREEN}.png" 2>/dev/null
    done
done

# 7. Shutdown when done
xcrun simctl shutdown "$SIMULATOR_UDID" 2>/dev/null || true
```

**Edge case — app crashes on launch:** If `xcrun simctl launch` fails or the app crashes immediately (check `xcrun simctl get_app_container` returns error), tell the user: "App crashed on launch in the simulator. Run it in Xcode to debug, then re-run `/appstore screenshots`."

### Step 4: Generate AI backgrounds with Gemini Nano Banana 2

**Skip this step if using solid background alternative (no Gemini API key).**

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

    # Check if response contains an image
    image_saved = False
    for part in response.parts:
        if part.inline_data is not None:
            image = part.as_image()
            image.save(f"build/backgrounds/{screen}_bg.png")
            image_saved = True
            break

    if not image_saved:
        print(f"Warning: Gemini returned no image for {screen}. Using fallback gradient.")
        # Create a solid color fallback with PIL
```

**Edge case — Gemini API error:** If `generate_content` raises an exception (quota exceeded, invalid key, model unavailable):
1. Log the error
2. Tell the user: "Gemini API error: [message]. Falling back to CSS gradient backgrounds for remaining screens."
3. Switch to the solid background alternative for remaining screens.

**Edge case — Gemini returns no image:** Sometimes the model returns only text (e.g., content policy refusal). Check `response.parts` for `inline_data` — if none found, use a solid color fallback for that screen.

Then upscale to exact target size:
```bash
mkdir -p build/backgrounds
sips -z 2796 1290 build/backgrounds/*_bg.png
```

### Step 5: Compose HTML pages

For each locale and screen, generate an HTML composition at 1x scale (430x932 CSS pixels = 1290x2796 at 3x):

- Full-bleed AI background image (or CSS gradient if using fallback)
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

**Edge case — Playwright crash:** If Playwright fails to launch Chromium, try reinstalling: `python3 -m playwright install chromium`. If it still fails, tell the user the error and suggest checking their system's Chromium compatibility.

### Step 7: Verify

```bash
# Check dimensions of all exported screenshots
for f in fastlane/screenshots/*/*_framed.png; do
    DIMS=$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | grep pixel | awk '{print $2}')
    WIDTH=$(echo "$DIMS" | head -1)
    HEIGHT=$(echo "$DIMS" | tail -1)
    if [ "$WIDTH" != "1290" ] || [ "$HEIGHT" != "2796" ]; then
        echo "WARNING: $f is ${WIDTH}x${HEIGHT}, expected 1290x2796"
    else
        echo "OK: $f"
    fi
done
```

**Edge case — wrong dimensions:** If screenshots are not 1290x2796, resize them:
```bash
sips -z 2796 1290 "fastlane/screenshots/{locale}/{screen}_framed.png"
```
Note: this may distort if the aspect ratio is different. Tell the user if resizing was needed.

---

## MODE: preview

Generate the HTML preview dashboard showing all metadata and screenshots.

### Prerequisite check

Check if `scripts/preview_appstore.py` exists. If not, download it:
```bash
mkdir -p scripts
curl -fsSL "https://raw.githubusercontent.com/mikwiseman/appstore-skill/main/scripts/preview_appstore.py" -o scripts/preview_appstore.py
chmod +x scripts/preview_appstore.py
```

Check if `fastlane/metadata/` exists. If not, tell the user: "No metadata found. Run `/appstore setup` and `/appstore metadata` first."

### Generate preview

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

**Edge case — partial metadata:** The preview handles missing files gracefully — it shows "Not set" for empty fields and a warning banner listing missing files. This is by design so the user can see what still needs to be filled in.

---

## MODE: upload

Upload everything to App Store Connect via fastlane.

### Prerequisite checks

1. **Fastlane installed:**
```bash
which fastlane 2>/dev/null && echo "OK" || echo "MISSING"
```
If missing: "Install fastlane: `gem install fastlane` or `brew install fastlane`"

2. **Fastlane config exists:**
```bash
test -f fastlane/Appfile && test -f fastlane/Fastfile && echo "OK" || echo "MISSING"
```
If missing: "Run `/appstore setup` first to create fastlane configuration."

3. **App Store Connect credentials:** Fastlane needs either:
   - An API key (`.json` file) referenced in the Fastfile, or
   - An `FASTLANE_USER` / `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD` environment variable, or
   - Interactive Apple ID login

If `fastlane deliver` fails with authentication errors, tell the user: "Fastlane authentication failed. Set up App Store Connect API key: https://docs.fastlane.tools/app-store-connect-api/"

### Upload

```bash
fastlane ios upload_all
```

Verify: Check output for "fastlane.tools finished successfully".

**Edge case — upload rejected:** If fastlane reports metadata validation errors (e.g., description too long, invalid category), show the specific error and tell the user which file to fix.

---

## MODE: full

Run the complete pipeline in order. This is the **zero to App Store** flow.

### 1. Preflight

Run all PREFLIGHT CHECKS. Show the status summary.

### 2. Setup

Check if `fastlane/` exists with locale directories. If not, run the **setup** mode to create the full directory structure. Ask the user for locales and contact info.

If `fastlane/` already exists, tell the user and skip setup.

### 3. Metadata

Run the **metadata** mode. Read the codebase, research via Exa (if available), generate all metadata files. Show summary and ask for approval.

### 4. Screenshots

Run the full **screenshots** pipeline (capture → Nano Banana 2 backgrounds or CSS gradients → compose → export).

If the user wants to skip screenshots (e.g., they already have them or don't have Gemini/Playwright set up), allow them to skip this step.

### 5. Preview

Run the **preview** mode to generate the HTML dashboard. The preview opens in the browser automatically.

**PAUSE HERE.** Tell the user:

> The App Store preview is open in your browser. Review the metadata and screenshots.
> When you're satisfied, say **"upload"** to push everything to App Store Connect.
> Or tell me what to change.

Wait for user confirmation before proceeding to upload.

### 6. Upload

After user confirms, run the **upload** mode.

**Edge case — user says skip upload:** That's fine. The metadata and screenshots are saved locally. They can run `/appstore upload` later.

### 7. Summary

Show a completion summary:

```
App Store Pipeline Complete!

Preflight: macOS ✓ | Xcode ✓ | Python ✓ | Exa [available/skipped] | Gemini [used/CSS fallback]
Setup: [created/already existed]
Metadata: [updated N locales / unchanged]
Screenshots: [N screens x M locales / skipped]
Preview: build/appstore_preview.html
Upload: [success/skipped]
```

---

## EXECUTION

Now execute the requested mode. Follow the steps in order. After each step, verify the output before proceeding.

If any step fails:
1. Show the full error message
2. Diagnose the root cause
3. Tell the user what went wrong and how to fix it
4. Ask if they want to retry or skip the step

**Write permission errors:** If any file write fails with a permission error (to `build/`, `fastlane/`, or `scripts/`), tell the user: "Permission denied writing to [path]. Check directory ownership and permissions: `ls -la [parent-dir]`"
