# Decisions

Why the code looks the way it does. Written during the refactor that split the
original single 333-line file into modules, so several entries record where the
first answer turned out to be wrong.

---

## Structure

**Split into `App` / `Models` / `Services` / `ViewModels` / `Views`.**
The original was one file. No test target, no dependency injection framework,
no protocol abstractions over `URLSession` — those would be machinery out of
proportion to a single-window menu bar utility.

**No Xcode test target.** A target plus scheme plus host app is more than this
needs. But the parts that are genuinely hard to reach by hand — Cloudflare
detection, percentage conversion, backoff arithmetic, error body shapes — are
covered by `./Tools/run-checks.sh`, which compiles the real sources against a
check harness in about two seconds. It found five real bugs during the refactor.

**Deployment target lowered 26.5 → 14.0.** Nothing in the code required 26.5,
which restricted the app to machines running the newest OS. 14.0 also unlocks
the `@Observable` macro.

---

## State and observation

**`@Observable`, not `ObservableObject` + `@AppStorage`.**
`@AppStorage` declared *inside* an observable class does not participate in that
class's change tracking, so credential edits did not reliably propagate. It also
can only write to UserDefaults, which is the wrong home for an account
credential. Credentials are now plain properties writing through to the Keychain
in `didSet`.

**`LoadState` enum instead of `statusText: String` + `isLoading: Bool`.**
Those two could contradict each other. One value, one truth.

**Typed `UsageError` instead of error strings.** Several failures are
indistinguishable at the HTTP layer but need different actions from the user.
Flattening them to a string sends people to the wrong fix.

---

## Credentials

**Keychain for secrets, UserDefaults for `orgId`.** `orgId` appears in every
claude.ai API URL; treating it as a secret would be theatre.

**File-based Keychain, not data-protection.** See [SECURITY.md](SECURITY.md) —
the data-protection Keychain needs an entitlement this app does not carry, and
fails every write with -34018 without it.

**Migration verifies before deleting.**

> **Incident.** The first implementation of the plaintext→Keychain migration
> called `setValue`, which returned `Void` and swallowed the `OSStatus`, then
> deleted the UserDefaults copy unconditionally. The Keychain write was failing
> with -34018. The result was that a live session key was destroyed with no
> copy anywhere.
>
> Two changes came out of it: `setValue` returns `Bool`, and the migration
> writes, reads back, compares, and only then deletes. On failure it keeps the
> plaintext copy and retries next launch.
>
> The process lesson is the more useful one: the migration was run against real
> data before it had ever been run against a sentinel. Destructive paths get
> tested with disposable data first.

---

## Networking

**`orgId` validated as a UUID before use.** It is interpolated into a URL path;
a pasted value containing `/` or `..` would otherwise retarget the request.

**Cloudflare detection inspects the body, not just the status.** A challenge
page can arrive with 403, 503, or even 200. Extracted into
`CloudflareChallengeDetector` so it can be checked against a captured challenge
page without a URL session.

**An expired session returns 403, not 401.** Verified against the live endpoint:

```json
{"error":{"type":"permission_error","message":"Invalid authorization",
          "details":{"error_code":"account_session_invalid"}}}
```

Phase 3 of this refactor mapped every non-challenge 403 to
`insufficientPermissions`, so an expired cookie told users their account lacked
permission and suggested Team/Enterprise admin access — exactly the misleading
message typed errors were introduced to eliminate. `APIErrorResponse` now
discriminates on `error_code`.

**Unrecognised structured errors surface the server's own wording** via
`.api(message:)` rather than a guess.

---

## `cf_clearance`

**Kept, but rarely needed.**

> **Correction.** This field was added because an early probe of the endpoint
> returned a Cloudflare challenge page, which looked like evidence that the API
> was gated behind Cloudflare. It was not. That probe used **python urllib**,
> whose TLS fingerprint Cloudflare blocks. `URLSession` from the signed app
> passes through and receives clean JSON from the same endpoint.
>
> The field remains because Cloudflare genuinely can challenge under load, from
> a VPN, or from an unusual IP — and it costs nothing when empty. But it is a
> fallback, not a normal requirement, and the documentation says so.

**The User-Agent stays hardcoded to Chrome on macOS.** A `cf_clearance` cookie
is bound to the User-Agent it was issued to, so this string and the browser the
cookie is copied from must agree. Making the UA configurable would be more UI
for a rare case; the README tells users to copy from Chrome instead.

---

## Refresh cadence

**`Task` loop, not `Timer`.** The old timer ran on the default run-loop mode, so
it stopped firing while a menu was tracked.

**Backoff, and a full stop for non-recoverable errors.** A fixed 180s poll
against a dead session generated roughly 480 identical requests a day.
Transient failures back off 360 → 720 → 1440 → 1800; non-recoverable ones stop
the loop until a credential changes or Refresh is pressed.

**Fetch at launch.** The old code only refreshed from the popover's `onAppear`,
so the menu bar read "Claude" for up to three minutes after login.

**Credential edits are debounced 1.2s.** `didSet` fires per keystroke;
restarting the poll loop each time would issue a request per character. The
Keychain write is *not* debounced — it is cheap, and losing the last keystroke
to a quit would be worse.

---

## Presentation

**The panel sizes to its content.** A plan reporting one quota now gets a 212pt
panel instead of 500pt of mostly empty space.

> A first attempt measured content with a `GeometryReader` and fed the result
> back into the frame. That is circular and collapsed to 1pt before the first
> layout pass. Caught by rendering it to a PNG and looking, not by reading it.

> **Correction.** The entry that replaced it claimed a `ScrollView` reports its
> content's ideal size, so `.frame(maxHeight:)` alone was enough. That is false,
> and it shipped: the popover opened as a 300x10 sliver showing nothing.
>
> `MenuBarExtra(.window)` sizes its panel by asking the content what size it
> wants with nothing imposed. A `ScrollView` does not pass its content's ideal
> height through that question — it answers with a fixed 10pt. `maxHeight` then
> clamps a number that never arrives. Measured through the hosting path
> `MenuBarExtra` uses, the old view returned the *same* size for every state:
> 300x0 for an unspecified proposal, 300x560 for an unbounded one. Content
> played no part in it.
>
> The height is now measured and applied explicitly, via a preference key. That
> is not a return to the circular version above: this reading is taken from the
> content *inside* the scroll view, where the vertical proposal is unbounded,
> and applied to the scroll view *around* it, so the measurement does not depend
> on the frame it sets.
>
> The process lesson: `./Tools/render-snapshots.sh` could never have caught
> this. It renders `PopoverContent`, not `PopoverView`, so panel sizing was
> never under test — and `ImageRenderer` proposes a concrete size anyway, which
> is the one thing that hides this bug. "Look at the PNGs" is necessary but not
> sufficient; a view that only misbehaves when asked for its *ideal* size has to
> be measured in the layout context that asks.

**Only the quotas the account reports are shown**, with an explicit empty state
when a successful response carries no quota data. Plans differ in what they
report; silently showing fewer rows leaves users unable to tell a plan
limitation from a bug.

**`QuotaBar` instead of `ProgressView(value:)`.** The stock control's tint
follows the system accent rather than the colour asked for, and it does not
survive offscreen rendering, which would have made the snapshot tool useless.

---

## Repository

**Team ID lives in a gitignored `Config.xcconfig`.** The committed
`Signing.xcconfig` ends with `#include? "Config.xcconfig"` — the `?` makes a
missing file a silent no-op, so a fresh clone builds with no warnings and no
setup. Verified by deleting the file and rebuilding.

**MIT licensed, unofficial caveat stated up front.** Anyone wiring a full-access
account credential into a third-party app deserves to know the endpoint is
undocumented and unsupported before they start.

---

## Still open

**The `Percentage` ambiguity.** Whether `utilization` is a `0.0…1.0` fraction or
a `0…100` number has never been confirmed against a captured success response.
The initialiser guesses from magnitude, which is wrong for genuine readings
below 1% (0.8% renders as 80%). The rule lives in one initialiser and is pinned
by a check so the behaviour is deliberate rather than accidental. Resolving it
needs one real response body.

**Team and Enterprise accounts are untested.** Org-scoped endpoints there may
require administrator access. The `.insufficientPermissions` path exists for it
but has never been exercised against a real Team account.
