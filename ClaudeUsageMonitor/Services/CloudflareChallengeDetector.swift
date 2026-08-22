import Foundation

/// Recognises a Cloudflare interstitial served in place of a real API response.
///
/// claude.ai sits behind Cloudflare, which answers challenged requests with an
/// HTML "Just a moment…" page. That page can arrive with a 403, a 503, or even
/// a 200, so the status code alone cannot tell you what happened — the body has
/// to be inspected. Getting this wrong sends the user to refresh their session
/// key when the actual fix is a `cf_clearance` cookie.
///
/// Kept as its own type so the detection can be exercised against a captured
/// challenge page without standing up a URL session.
enum CloudflareChallengeDetector {
    /// Markers that appear in Cloudflare's managed-challenge page. Matching any
    /// one is enough; they are checked case-insensitively.
    static let markers = [
        "just a moment",
        "_cf_chl_opt",
        "cf-browser-verification",
        "challenges.cloudflare.com",
        "enable javascript and cookies to continue",
    ]

    /// Only the head of the body is examined — the markers all appear well
    /// inside the first few kilobytes, and this avoids scanning a large payload.
    static let inspectedByteCount = 8192

    /// Whether `body` looks like a challenge page.
    ///
    /// - Parameter contentType: the response's `Content-Type`, if any. A
    ///   response that is not HTML is never a challenge page, and checking this
    ///   first avoids decoding JSON bodies as text.
    static func isChallenge(body: Data, contentType: String?) -> Bool {
        guard let contentType, contentType.lowercased().contains("text/html") else {
            return false
        }
        guard let head = String(data: body.prefix(inspectedByteCount), encoding: .utf8)?.lowercased() else {
            return false
        }
        return markers.contains { head.contains($0) }
    }
}
