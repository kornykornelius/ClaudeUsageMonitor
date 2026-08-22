# ClaudeUsageMonitor

A macOS **menu-bar-only** app (no Dock icon) showing claude.ai usage quotas.
SwiftUI, `MenuBarExtra`, single target, no dependencies.

Start with [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the module map and
[docs/DECISIONS.md](docs/DECISIONS.md) for why things are the way they are.
User-facing setup lives in [README.md](README.md); credential handling in
[docs/SECURITY.md](docs/SECURITY.md). Do not duplicate that content here.

## Project facts

- **macOS 14.0+**, Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (`objectVersion 77`).
  **Files added under `ClaudeUsageMonitor/` are compiled automatically** — there
  is no file list in `project.pbxproj` to update.
- Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`). Plist keys are set
  as `INFOPLIST_KEY_*` build settings in **both** Debug and Release.
- `DEVELOPMENT_TEAM` is **not** in `project.pbxproj`. It comes from the
  committed `Signing.xcconfig`, which optionally includes a gitignored
  `Config.xcconfig`. A clone without that file builds cleanly.
- There is **no app icon image**. `Assets.xcassets/AppIcon.appiconset/` contains
  only `Contents.json`. The menu bar uses the SF Symbol `brain.head.profile`;
  keep SF Symbols so they adapt to light and dark menu bars.

## After any code change: quit, rebuild, relaunch

A running instance does not pick up changes.

```bash
pkill -x ClaudeUsageMonitor
xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/ClaudeUsageMonitor-*/Build/Products/Debug/ClaudeUsageMonitor.app
```

In Xcode, `Cmd + R` does all three. There is no Dock icon — that is expected.

Confirm the agent flag survived a build:

```bash
/usr/libexec/PlistBuddy -c "Print :LSUIElement" \
  ~/Library/Developer/Xcode/DerivedData/ClaudeUsageMonitor-*/Build/Products/Debug/ClaudeUsageMonitor.app/Contents/Info.plist
# expected: true
```

Confirm it is actually running as an agent:

```bash
osascript -e 'tell application "System Events" to get background only of (first process whose name is "ClaudeUsageMonitor")'
# expected: true
```

### Updating a copy in /Applications

That copy is a frozen snapshot; Debug builds do not update it.

```bash
pkill -x ClaudeUsageMonitor
xcodebuild -project ClaudeUsageMonitor.xcodeproj -scheme ClaudeUsageMonitor -configuration Release build
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeUsageMonitor-*/Build/Products/Release/ClaudeUsageMonitor.app /Applications/
open /Applications/ClaudeUsageMonitor.app
```

## Verifying changes

```bash
./Tools/run-checks.sh          # ~50 checks; run after touching Models/ or Services/
./Tools/render-snapshots.sh    # PNG per popover state; run after touching Views/
```

**Look at the rendered PNGs.** During the refactor they caught a sizing bug that
collapsed the panel to 1pt and a duplicated UI label, neither of which was
visible from reading the code.

`ImageRenderer` does not draw `TextField`, `SecureField` or `ProgressView` —
they appear as yellow placeholders. That is a rendering limitation, not a bug.

The app logs under subsystem `woeichwan.ClaudeUsageMonitor`:

```bash
log show --predicate 'subsystem == "woeichwan.ClaudeUsageMonitor"' --last 1h --info
```

## Working rules

- **Never hard-code or commit credentials.** `sessionKey` grants full account
  access. It lives in the Keychain; `orgId` in UserDefaults.
- **Test destructive paths with a sentinel value before real data.** The
  credential migration destroyed a live session key because it was run against
  real data before it had ever been run against a throwaway one. Seed the
  container plist, verify, then clean up.
- **Do not probe the claude.ai API with `curl` or python.** Cloudflare blocks
  their TLS fingerprints and returns a challenge page, which looks like an API
  behaviour but is not. Use `URLSession` — see `Tools/snapshots/main.swift` for
  a working pattern.
- Percentage conversion is unresolved; the rule lives in one initialiser in
  `UsageSnapshot.swift`. If a real success response is ever captured, fix it
  there and delete the warning.
