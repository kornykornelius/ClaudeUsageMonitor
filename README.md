# ClaudeUsageMonitor

A macOS menu-bar app that shows your claude.ai usage quotas at a glance — the
current 5-hour session window, the weekly limits, and any extra usage credits.
No Dock icon, no window: just a percentage next to a brain icon in the menu bar.

> **Unofficial.** This app reads an undocumented claude.ai endpoint using your
> browser session cookie. It is not affiliated with Anthropic, may break without
> notice, and your `sessionKey` grants full access to your Claude account —
> treat it as a password.

## What it shows

| Section | Source field | Notes |
| --- | --- | --- |
| Current 5-hour session | `five_hour` | The rolling session window |
| All models, 7 days | `seven_day` | Weekly total |
| Sonnet, 7 days | `seven_day_sonnet` | Only on plans that report it |
| Opus, 7 days | `seven_day_opus` | Only on plans that report it |
| Extra usage credits | `extra_usage` | Balance, monthly cap, expiry |

Sections your plan does not report are simply not shown.

### Scope

This reads **claude.ai subscription quotas only**. It does *not* track
Anthropic API spend from `console.anthropic.com` — that is a different service
with different billing and different authentication. Claude Code usage *does*
count here when you are on a Pro or Max subscription rather than API billing.

## Requirements

- macOS 14.0 (Sonoma) or later
- A claude.ai account you can log in to in a browser

## Getting your credentials

The app needs two values, and optionally a third. All of them come from a
browser where you are already logged in to claude.ai.

You will use your browser's developer tools. Open them with **`Cmd + Option + I`**
on macOS (`F12` or `Ctrl + Shift + I` elsewhere).

| Browser | Where cookies live |
| --- | --- |
| Chrome / Edge / Brave / Arc | **Application** tab → sidebar → **Storage** → **Cookies** |
| Firefox | **Storage** tab → **Cookies** |
| Safari | **Storage** tab → **Cookies** — first enable Safari → Settings → Advanced → *Show features for web developers* |

### 1. `sessionKey` — required

Your claude.ai session cookie. This is what authenticates the app as you.

1. Log in to <https://claude.ai>.
2. Open developer tools (`Cmd + Option + I`).
3. Go to the cookies panel for your browser (see the table above) and select
   the `https://claude.ai` origin.
4. Find the cookie named **`sessionKey`**.
5. Right-click its **Value** cell and choose *Copy value* (or double-click the
   cell to select the text, then `Cmd + C`).

The value is a long string beginning `sk-ant-sid01-`.

> **`document.cookie` will not work.** `sessionKey` is marked `HttpOnly`, which
> deliberately hides it from JavaScript. If you try to read it from the Console
> you will get nothing back. Use the cookies panel.

### 2. Organization ID — required

A UUID that looks like `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`. Every claude.ai
account has one, including personal accounts.

**Easiest method:** with your logged-in browser, open

```
https://claude.ai/api/organizations
```

It returns JSON. Copy the value of the `uuid` field.

**Alternative, via developer tools:**

1. On <https://claude.ai>, open developer tools and go to the **Network** tab.
2. Reload the page.
3. Type `organizations` into the filter box.
4. Click any matching request. Its URL has the form
   `https://claude.ai/api/organizations/<orgId>/…` — the UUID segment after
   `/organizations/` is your organization ID.

### 3. `cf_clearance` — optional, and usually unnecessary

**Leave this empty unless the app tells you otherwise.**

claude.ai sits behind Cloudflare, but the app's requests pass through normally.
This field exists only for the uncommon case where Cloudflare actively
challenges you — under heavy load, from a VPN, or from an unusual IP address.
You will know, because the popover will say *"Blocked by Cloudflare"*.

If that happens, copy it exactly like `sessionKey`, from the same cookies
panel — look for the cookie named **`cf_clearance`**.

> **Copy it from Chrome.** A `cf_clearance` cookie is bound to the IP address
> *and* the browser User-Agent it was issued to. The app identifies itself as
> Chrome on macOS, so a `cf_clearance` issued to Safari or Firefox will not
> validate. It also stops working when your IP changes — switching networks or
> connecting to a VPN means fetching a fresh one.

### Entering them

Click the brain icon in the menu bar. The **Credentials** section at the bottom
of the popover has a field for each value. Paste and they are saved
immediately — there is no Save button.

`sessionKey` and `cf_clearance` are stored in your login Keychain.
The organization ID is not a secret (it appears in every claude.ai API URL) and
is stored in the app's preferences.

### Keeping them working

`sessionKey` is a session cookie, so it dies when the session does:

- **Logging out of claude.ai invalidates it.** If you log out in your browser,
  the app stops working until you paste a fresh key.
- Sessions expire on their own after a period of inactivity.
- If the app reports an expired session, repeat step 1 to get a new value.

## Troubleshooting

| The popover says | What it means | What to do |
| --- | --- | --- |
| **Session Expired** | Your `sessionKey` is no longer valid — usually because you logged out of claude.ai, or the session aged out. | Copy a fresh `sessionKey` (step 1). |
| **Invalid Organization ID** | The value isn't a well-formed UUID. | Re-copy it (step 2). It must look like `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`. |
| **Organization Not Found** | No organization with that ID is visible to this session. | Check that the `sessionKey` and `orgId` come from the *same* account. |
| **Access Denied** | The session is valid but not allowed to read that organization's usage. | Team and Enterprise accounts may require administrator access. |
| **Blocked by Cloudflare** | Cloudflare is challenging requests. | Supply `cf_clearance` (step 3). |
| **claude.ai returned no quota data** | The request succeeded but your plan reports no quotas. | Not an error. Plans differ in what they report. |
| **Offline** / **Request Timed Out** | Network problem. | The app backs off and retries automatically. |

After a non-recoverable error the app **stops polling** until you change a
credential or press Refresh — it will say so. This is deliberate: retrying an
expired session on a timer just generates hundreds of identical failed requests
a day.

For more detail, the app logs to the unified log:

```bash
log show --predicate 'subsystem == "woeichwan.ClaudeUsageMonitor"' --last 1h --info
```

Credentials are never written to the log.

## Security

- **Treat `sessionKey` like a password.** Anyone holding it can act as you on
  claude.ai — read your conversations, use your quota, change your settings.
- Secrets are stored in the macOS login Keychain, not in preferences files.
- Never commit these values to a repository or paste them into a shared
  document, an issue, or a screenshot.
- The app talks to exactly one host, `claude.ai`, over HTTPS. It sends nothing
  anywhere else and has no analytics.
- It runs in the App Sandbox with only the outgoing-network entitlement.

## Building from source

```bash
git clone <this repo>
cd ClaudeUsageMonitor
xcodebuild -project ClaudeUsageMonitor.xcodeproj \
           -scheme ClaudeUsageMonitor \
           -configuration Debug build
```

Then launch the built app:

```bash
open ~/Library/Developer/Xcode/DerivedData/ClaudeUsageMonitor-*/Build/Products/Debug/ClaudeUsageMonitor.app
```

Or open `ClaudeUsageMonitor.xcodeproj` in Xcode and press `Cmd + R`.

The app appears in the **menu bar**, not the Dock. That is intentional — it is
marked `LSUIElement`.

### Signing

The project builds and runs with no signing setup: Xcode falls back to *Sign to
Run Locally*. To sign with your own Apple Developer team, create a
`Config.xcconfig` in the repository root:

```bash
echo 'DEVELOPMENT_TEAM = YOURTEAMID' > Config.xcconfig
```

That file is gitignored and is picked up automatically by `Signing.xcconfig`.
Your Team ID is at <https://developer.apple.com/account> under Membership
Details, or in Xcode under Settings → Accounts.

### Development tooling

There is no Xcode test target. Two scripts cover the parts that are otherwise
awkward to verify:

```bash
./Tools/run-checks.sh          # ~50 correctness checks against the real sources
./Tools/render-snapshots.sh    # every popover state rendered to PNG
```

Xcode previews work for all seven popover states.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — module map, data flow, and the
  types worth knowing about
- [docs/DECISIONS.md](docs/DECISIONS.md) — why the code looks the way it does,
  including where the first answer turned out to be wrong
- [docs/SECURITY.md](docs/SECURITY.md) — credential handling, storage, and
  network behaviour

## Known limitations

- **Sub-1% readings may display incorrectly.** The API's `utilization` field has
  not been confirmed to be a fraction or a percentage, so the app guesses from
  magnitude. A genuine 0.8% reading shows as 80%. See
  [docs/DECISIONS.md](docs/DECISIONS.md).
- **Team and Enterprise accounts are untested.** Organization-scoped endpoints
  there may require administrator access.
- **The endpoint is undocumented** and can change or disappear without notice.

## License

[MIT](LICENSE).
