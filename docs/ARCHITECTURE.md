# Architecture

A single-target SwiftUI menu bar app. No dependencies, no package manager, no
Xcode test target. Roughly 1,000 lines of Swift across four layers.

## Layout

```
ClaudeUsageMonitor/
  App/
    ClaudeUsageMonitorApp.swift    @main, MenuBarExtra scene, menu bar label
  Models/
    UsageResponse.swift            wire format (Codable, mirrors the JSON)
    APIErrorResponse.swift         wire format for error bodies
    UsageSnapshot.swift            domain model + Percentage + Timestamp
    UsageSnapshot+Samples.swift    sample data for previews and snapshots
    LoadState.swift                LoadState + UsageError
    RefreshSchedule.swift          poll cadence arithmetic (pure)
  Services/
    CredentialStore.swift          Keychain access + legacy migration
    UsageAPIClient.swift           the one network call
    CloudflareChallengeDetector.swift
  ViewModels/
    UsageViewModel.swift           state, credentials, the poll loop
  Views/
    PopoverView.swift              scroll chrome + sizing
    PopoverContent.swift *         (same file) the actual content
    QuotaSectionView.swift         one quota row + QuotaBar
    CredentialsView.swift          three secure/plain fields
```

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (`objectVersion 77`),
so files added under `ClaudeUsageMonitor/` are compiled automatically. There is
no file list in `project.pbxproj` to keep in sync.

## Data flow

```
                 ┌──────────────────┐
   Keychain ────▶│                  │
                 │  UsageViewModel  │◀──── poll loop (Task, not Timer)
 UserDefaults ──▶│                  │
   (orgId)       └────────┬─────────┘
                          │ orgId + cookies
                          ▼
                 ┌──────────────────┐      ┌───────────────────────────┐
                 │  UsageAPIClient  │─────▶│ claude.ai/api/organizations
                 └────────┬─────────┘      │ /{orgId}/usage            │
                          │                └───────────────────────────┘
        UsageResponse ────┤ or UsageError
                          ▼
                 ┌──────────────────┐
                 │  UsageSnapshot   │  domain model: only the quotas
                 └────────┬─────────┘  this account actually reports
                          ▼
                     LoadState  ──▶  PopoverContent
```

The wire types (`UsageResponse`, `APIErrorResponse`) exist only to be decoded
and immediately converted. Views never see them. That boundary is what lets the
undocumented endpoint change shape without the UI caring.

## The pieces worth knowing about

### `LoadState`

```swift
enum LoadState {
    case needsSetup
    case loading
    case refreshing(UsageSnapshot, fetchedAt: Date)
    case loaded(UsageSnapshot, fetchedAt: Date)
    case failed(UsageError)
}
```

Replaced a `statusText: String` plus a separate `isLoading: Bool`, which could
disagree with each other. `refreshing` carries the previous snapshot so the
popover does not blank out on every poll.

### `UsageError`

Every failure path is one of these. The point is not tidiness — it is that
several failures are identical at the HTTP layer but need completely different
things from the user:

| Situation | Wire | Maps to |
| --- | --- | --- |
| Cloudflare interstitial | 403/503/200 + HTML | `.cloudflareChallenge` |
| Expired session cookie | **403** + `error_code: account_session_invalid` | `.sessionExpired` |
| Account lacks permission | 403, other body | `.insufficientPermissions` |
| Bad org UUID | caught locally | `.invalidOrganizationID` |

Note the second row. An expired cookie returns **403, not 401**. Distinguishing
it from a genuine permission problem requires parsing the response body — see
`APIErrorResponse`.

`isTransient` decides whether retrying can help. It drives the poll loop.

### `UsageSnapshot`

Holds only the quotas the account reported. Which ones exist varies by plan, so
a missing entry means "this account does not report that", not an error.
`isEmpty` distinguishes a successful-but-empty response from a failure.

### `Percentage`

⚠️ **Contains an unresolved ambiguity.** No real usage response has been
captured, so whether `utilization` is a `0.0…1.0` fraction or a `0…100` number
is unknown. The initialiser guesses from magnitude. This is wrong in exactly one
case: a genuine reading below 1% renders 100× too large (0.8% shows as 80%).

The rule lives in one initialiser. Once a real response is captured, change that
body and delete the warning; nothing else needs to move.

### `RefreshSchedule`

Pure functions, separated from the view model so the cadence can be checked
directly rather than by timing a running app.

```
success            180s, or sooner if a quota resets before then (floor 30s)
transient failure  360 → 720 → 1440, capped at 1800
non-recoverable    stop polling entirely
```

That last row matters. An expired session fails identically forever; retrying on
a timer only burns battery. The loop idles until a credential changes or the
user presses Refresh.

### `CredentialStore`

Keychain-backed. Uses the **file-based** Keychain, not the data-protection one —
`kSecUseDataProtectionKeychain` requires a `keychain-access-groups` entitlement
this app does not carry, and every write fails with `errSecMissingEntitlement`
(-34018) without it. See [SECURITY.md](SECURITY.md).

`setValue` returns `Bool` rather than swallowing `OSStatus`, because the
migration path deletes the caller's only other copy of a credential and must be
able to tell whether the write landed.

### View sizing

`PopoverView` is scroll chrome; `PopoverContent` is everything inside it. A
`ScrollView` reports its content's ideal size as its own, so `.frame(maxHeight:)`
is enough to size the panel to its content and scroll only past the cap.

Do not reach for a `GeometryReader` that feeds a measured height back into the
frame — that is circular and collapses to zero before the first layout pass.

The split also exists because `ImageRenderer` lays out `ScrollView` content but
does not draw it, which would make the snapshot tool useless.

## Development tooling

There is no Xcode test target — see [DECISIONS.md](DECISIONS.md). Two scripts
cover what would otherwise be untestable:

```bash
./Tools/run-checks.sh          # ~50 correctness checks, about two seconds
./Tools/render-snapshots.sh    # every popover state to PNG
```

`run-checks.sh` compiles the real `Models/` and `Services/` sources — not
copies — against `Tools/checks/main.swift`. It exercises Cloudflare detection
against a captured challenge page, `Percentage` edge cases, snapshot
construction from partial and all-null responses, backoff arithmetic, and error
body parsing.

Between them these caught five real bugs during the refactor, including a
sizing implementation that collapsed to 1pt and a duplicated UI label.

Xcode previews work for all seven popover states via `UsageViewModel.preview(_:)`,
which touches neither Keychain nor network.
