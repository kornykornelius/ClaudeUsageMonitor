# Security

## What the credentials are worth

`sessionKey` is a claude.ai session cookie. Anyone holding it can act as you on
claude.ai: read your conversations, spend your quota, change your settings.
**It is equivalent to your password, and should be handled like one.**

It is not scoped, not read-only, and cannot be limited to usage data. The app
needs it because the endpoint it reads has no other authentication mechanism —
it is claude.ai's own front-end API, not a public one with issuable tokens.

`cf_clearance` is a Cloudflare clearance cookie. It is not an account
credential, but it is tied to your IP address and browser fingerprint.

`orgId` is **not** a secret. It appears in the URL of every claude.ai API
request the web app makes.

## Where they are stored

| Value | Location | Rationale |
| --- | --- | --- |
| `sessionKey` | login Keychain | Account credential |
| `cf_clearance` | login Keychain | Fingerprint-bound, treated as sensitive |
| `orgId` | app preferences | Not a secret |

Keychain items are generic passwords under service `woeichwan.ClaudeUsageMonitor`,
with the credential name as the account.

### Why the file-based Keychain

The app uses the **file-based** Keychain rather than the data-protection
Keychain (`kSecUseDataProtectionKeychain`).

The data-protection Keychain is the more modern API and would be the default
recommendation, but on macOS it requires a `keychain-access-groups` entitlement.
This app does not carry one, and with it requested, **every write fails with
`errSecMissingEntitlement` (-34018)**. A sandboxed, signed app can use the
file-based Keychain for its own items with no additional entitlement, and the
App Sandbox still confines those items to this application.

Adding the entitlement would mean pinning a team identifier prefix into the
project, which conflicts with keeping the repository free of account-specific
values. If that trade changes, the store is one file.

### Migration out of plaintext

Earlier versions stored `sessionKey` in `UserDefaults` via `@AppStorage`, in
plaintext, in the app's container preferences file. On launch the app moves any
such value into the Keychain.

The plaintext copy is deleted **only after the Keychain value has been written
and read back intact**. If the Keychain is unavailable the plaintext copy is
deliberately left in place and the migration retries next launch. A credential
sitting in UserDefaults is a problem; destroying the user's only copy of it is a
worse one.

> This ordering was learned the hard way. An earlier implementation wrote,
> ignored the returned `OSStatus`, and deleted the original regardless — which
> destroyed a live credential when the write failed with -34018. `setValue` now
> returns `Bool` and the caller checks it.

## Network behaviour

- Exactly one host is contacted: `claude.ai`, over HTTPS.
- One endpoint: `GET /api/organizations/{orgId}/usage`.
- No analytics, no telemetry, no crash reporting, no third-party services.
- No dependencies, so no transitive supply chain.

`orgId` is validated as a UUID before being interpolated into the URL path.
Beyond catching typos, this prevents a pasted value containing `/` or `..` from
retargeting the request at a different endpoint.

## Sandbox and entitlements

The app runs in the App Sandbox with the Hardened Runtime enabled:

```
com.apple.security.app-sandbox                  true
com.apple.security.network.client               true
com.apple.security.files.user-selected.read-only true
```

There is no incoming network entitlement, no file system access beyond the
container, no camera, microphone, contacts, or location.

## Logging

The app logs to the unified log under subsystem `woeichwan.ClaudeUsageMonitor`.

Credentials are never logged. When a request fails, the app records the status
code, content type, response size, and whether the body looked like a Cloudflare
challenge — but **not the body itself**, since an error payload may echo account
details.

To read the log:

```bash
log show --predicate 'subsystem == "woeichwan.ClaudeUsageMonitor"' --last 1h --info
```

## Your responsibilities

- Never commit `sessionKey` or `cf_clearance` to a repository.
- Never paste them into an issue, a chat, or a screenshot.
- Logging out of claude.ai invalidates the session key. That is the fastest way
  to revoke access if you believe it has leaked.
- The repository's `.gitignore` covers `Config.xcconfig`, `*.env`, and
  `Secrets.swift`, but the app never writes credentials to disk in the working
  tree, so there is nothing in the repo to leak by accident.

## Reporting a problem

This is an unofficial personal project reading an undocumented endpoint. If you
find a security issue in *this app*, open an issue. Do not report issues with
claude.ai itself here — those belong with Anthropic.
