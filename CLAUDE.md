# ClaudeUsageMonitor

A macOS **menu-bar-only** app (no Dock icon) that shows Claude.ai usage quotas. Built with SwiftUI using `MenuBarExtra`. The app is marked as an agent via the `INFOPLIST_KEY_LSUIElement = YES` build setting in `project.pbxproj`, so it only appears in the menu bar.

## Project layout

- `ClaudeUsageMonitor/ClaudeUsageMonitorApp.swift` — the entire app (models, view model, UI) lives in this single file.
- `ClaudeUsageMonitor.xcodeproj` — Xcode project. Info.plist is auto-generated (`GENERATE_INFOPLIST_FILE = YES`), so plist keys are set as `INFOPLIST_KEY_*` build settings, not in a plist file.

## After any code change: how to run the app again

The running app does NOT pick up code changes. You must quit the old instance, rebuild, and relaunch.

### Step 1 — Quit the running app

Because there is no Dock icon, quit it one of these ways:

- Click the brain icon in the **menu bar** → click the **Quit** button in the popover, or
- Run from terminal:

```bash
pkill -x ClaudeUsageMonitor
```

(In Xcode, `Cmd + .` stops the running debug session, which also quits the app.)

### Step 2 — Rebuild and relaunch

**Option A — Xcode (recommended for development):**

1. Open the project: double-click `ClaudeUsageMonitor.xcodeproj`, or run `open ClaudeUsageMonitor.xcodeproj`.
2. Press **`Cmd + R`** (Product → Run). This builds and launches the new version in one step.
   - **`Cmd + B`** (Product → Build) builds only, without launching.
   - **`Cmd + Shift + K`** (Product → Clean Build Folder) if the build behaves strangely and you want a clean rebuild.
3. The app appears in the **menu bar** (brain icon), not the Dock — that is expected.

**Option B — Command line only (no Xcode UI):**

```bash
xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor -configuration Debug build
```

Then launch the built app:

```bash
open ~/Library/Developer/Xcode/DerivedData/ClaudeUsageMonitor-*/Build/Products/Debug/ClaudeUsageMonitor.app
```

### Step 3 — If a copy is installed in /Applications

The copy in `/Applications` is a frozen snapshot; rebuilding in Xcode does not update it. To update the installed copy:

1. Quit the running app (Step 1).
2. Build a **Release** version: in Xcode use Product → Archive, or from the command line:

```bash
xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor -configuration Release build
```

3. Replace the old copy:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeUsageMonitor-*/Build/Products/Release/ClaudeUsageMonitor.app /Applications/
```

4. Relaunch: `open /Applications/ClaudeUsageMonitor.app`

## Credentials required

The app calls `https://claude.ai/api/organizations/{orgId}/usage` and needs two values, entered in the **Credentials** section at the bottom of the menu bar popover:

### 1. `sessionKey` (session cookie)

This is your claude.ai browser session cookie, starting with `sk-ant-sid01-...`.

How to get it (Chrome / Edge / Brave):

1. Log in to [claude.ai](https://claude.ai) in your browser.
2. Open Developer Tools: **`Cmd + Option + I`** (or right-click → Inspect).
3. Go to the **Application** tab (in Safari: **Storage** tab, after enabling the Develop menu in Safari Settings → Advanced).
4. In the left sidebar expand **Cookies** → click `https://claude.ai`.
5. Find the cookie named **`sessionKey`** and copy its **Value** (the long `sk-ant-sid01-...` string).

### 2. Organization ID (`orgId`)

A UUID like `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.

How to get it:

1. While logged in to claude.ai with Developer Tools open, go to the **Network** tab and reload the page.
2. Filter requests by `organizations`. Any API request URL will look like `https://claude.ai/api/organizations/<orgId>/...` — the UUID segment after `/organizations/` is your org ID.
   - Alternative: open `https://claude.ai/api/organizations` directly in the logged-in browser and read the `uuid` field from the JSON response.

### Notes on credentials

- Paste both values into the app's popover fields (sessionKey is a secure field). They are stored in `UserDefaults` via `@AppStorage` and persist across launches.
- The sessionKey **expires** when you log out or the session ends — if the app shows `HTTP Error 401/403 (Check Credentials)`, grab a fresh cookie value.
- **Never commit these values to the repo** or hard-code them in source. They grant full access to the claude.ai account.

## Verifying the menu-bar-only behavior

After launching, the app must show a brain icon in the menu bar and **no Dock icon**. If a Dock icon appears, an old build is running — quit it and relaunch the freshly built app. To confirm the built app has the agent flag:

```bash
/usr/libexec/PlistBuddy -c "Print :LSUIElement" ~/Library/Developer/Xcode/DerivedData/ClaudeUsageMonitor-*/Build/Products/Debug/ClaudeUsageMonitor.app/Contents/Info.plist
```

Expected output: `true`

## Notes for future changes

- Plist keys (e.g., `LSUIElement`) must be added as `INFOPLIST_KEY_*` build settings in **both** Debug and Release configurations in `project.pbxproj`.
- The menu bar icon uses the SF Symbol `brain.head.profile`; keep SF Symbols (they adapt to light/dark menu bars automatically).
- App icon: single 1024×1024 sRGB PNG in the `AppIcon` asset (Xcode "Single Size" mode generates the rest).
