import Foundation

/// What the popover should be showing right now.
///
/// This replaces a `statusText: String` plus a separate `isLoading: Bool`,
/// which could contradict each other — "Updated" while still loading, an error
/// string alongside stale data. One value, one truth.
enum LoadState: Equatable {
    /// Credentials are missing; there is nothing to fetch yet.
    case needsSetup
    /// A request is in flight and there is no previous result to show.
    case loading
    /// A request is in flight, but earlier data is still worth displaying.
    case refreshing(UsageSnapshot, fetchedAt: Date)
    case loaded(UsageSnapshot, fetchedAt: Date)
    case failed(UsageError)

    /// The most recent snapshot, if any, regardless of what is happening now.
    var snapshot: UsageSnapshot? {
        switch self {
        case .loaded(let snapshot, _), .refreshing(let snapshot, _): snapshot
        case .needsSetup, .loading, .failed: nil
        }
    }

    var isBusy: Bool {
        switch self {
        case .loading, .refreshing: true
        case .needsSetup, .loaded, .failed: false
        }
    }

    var error: UsageError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

/// A failure that the user can act on, or at least understand.
///
/// The point of enumerating these rather than passing a string around is that
/// several of them look identical at the HTTP layer but need completely
/// different responses from the user. A 403 carrying a Cloudflare challenge
/// page means "fetch a cf_clearance cookie"; a bare 403 means "your account
/// cannot read this organisation". Telling someone to refresh their session key
/// in the second case sends them somewhere useless.
enum UsageError: Error, Equatable {
    /// The organisation ID is not a well-formed UUID. Caught locally, before
    /// any request is sent.
    case invalidOrganizationID
    /// 401 — the session cookie is expired or wrong.
    case sessionExpired
    /// 403 with a Cloudflare challenge body.
    case cloudflareChallenge
    /// 403 without a challenge body — authenticated, but not allowed.
    case insufficientPermissions
    /// 404 — no organisation with that ID is visible to this session.
    case organizationNotFound
    /// 429, with the server's `Retry-After` if it supplied one.
    case rateLimited(retryAfter: Date?)
    /// Any other non-success status.
    case server(status: Int)
    /// No usable network connection.
    case offline
    /// The request exceeded its timeout.
    case timedOut
    /// A 200 whose body could not be decoded as the expected JSON.
    case malformedResponse
    /// A structured error from claude.ai that we do not specifically
    /// recognise. The server's own wording is shown rather than a guess.
    case api(message: String)

    /// Short line for the menu bar and the top of the popover.
    var title: String {
        switch self {
        case .invalidOrganizationID: "Invalid Organization ID"
        case .sessionExpired: "Session Expired"
        case .cloudflareChallenge: "Blocked by Cloudflare"
        case .insufficientPermissions: "Access Denied"
        case .organizationNotFound: "Organization Not Found"
        case .rateLimited: "Rate Limited"
        case .server(let status): "Server Error (\(status))"
        case .offline: "Offline"
        case .timedOut: "Request Timed Out"
        case .malformedResponse: "Unexpected Response"
        case .api: "claude.ai Error"
        }
    }

    /// What to actually do about it.
    var recoverySuggestion: String {
        switch self {
        case .invalidOrganizationID:
            "The Organization ID must be a UUID like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx. Open claude.ai/api/organizations while logged in and copy the uuid field."
        case .sessionExpired:
            "Copy a fresh sessionKey cookie from claude.ai in your browser. Logging out invalidates the old one."
        case .cloudflareChallenge:
            "Cloudflare is challenging requests. Copy the cf_clearance cookie from Chrome on claude.ai and paste it below. It is tied to your IP address, so refresh it after changing networks."
        case .insufficientPermissions:
            "This session is valid but not allowed to read that organization's usage. Team and Enterprise accounts may require administrator access."
        case .organizationNotFound:
            "No organization with that ID is visible to this session. Check the Organization ID, and that the sessionKey belongs to the same account."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Too many requests. Retrying automatically after \(Timestamp.short(retryAfter))."
            } else {
                "Too many requests. The app will back off and retry automatically."
            }
        case .server:
            "claude.ai returned an error. This is usually temporary; the app will retry."
        case .offline:
            "No network connection."
        case .timedOut:
            "claude.ai did not respond in time. The app will retry."
        case .malformedResponse:
            "claude.ai returned data in an unexpected format. The endpoint is undocumented and may have changed."
        case .api(let message):
            message
        }
    }

    /// Whether retrying on a timer stands any chance of helping. A bad
    /// organisation ID will fail identically forever; a 503 will not.
    var isTransient: Bool {
        switch self {
        case .rateLimited, .server, .offline, .timedOut: true
        case .invalidOrganizationID, .sessionExpired, .cloudflareChallenge,
             .insufficientPermissions, .organizationNotFound, .malformedResponse, .api: false
        }
    }
}
