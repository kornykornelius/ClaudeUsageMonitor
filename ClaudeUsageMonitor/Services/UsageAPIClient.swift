import Foundation
import os

/// Fetches usage from the claude.ai web API.
///
/// This is an undocumented endpoint intended for claude.ai's own front end, so
/// the request deliberately looks like one the web app would make: a browser
/// User-Agent, a same-origin `Sec-Fetch-Site`, and the session cookie.
struct UsageAPIClient {
    /// The User-Agent the app presents.
    ///
    /// - Important: A `cf_clearance` cookie is bound to the User-Agent it was
    ///   issued to, so this string and the browser the user copies that cookie
    ///   from have to agree. The README tells users to copy it from Chrome
    ///   because of this value.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"

    private static let logger = Logger(subsystem: "woeichwan.ClaudeUsageMonitor", category: "UsageAPIClient")

    var session: URLSession = .shared
    var timeout: TimeInterval = 15

    /// Fetches and decodes the current usage snapshot.
    ///
    /// - Throws: `UsageError` for every failure path, so callers never have to
    ///   interpret raw status codes or `URLError`s.
    func fetchUsage(orgId: String, sessionKey: String, cfClearance: String) async throws -> UsageSnapshot {
        let organization = orgId.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate before interpolating into a URL path. Beyond catching
        // typos, this stops a pasted value containing "/" or ".." from
        // retargeting the request at a different endpoint.
        guard UUID(uuidString: organization) != nil else {
            throw UsageError.invalidOrganizationID
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "claude.ai"
        components.path = "/api/organizations/\(organization)/usage"

        guard let url = components.url else {
            throw UsageError.invalidOrganizationID
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(Self.cookieHeader(sessionKey: sessionKey, cfClearance: cfClearance), forHTTPHeaderField: "Cookie")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.mapped(error)
        } catch {
            throw UsageError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.malformedResponse
        }

        if http.statusCode != 200 {
            // The endpoint is undocumented, so when it refuses a request the
            // shape of that refusal is the only evidence available for
            // diagnosing it. Status, content type, size and the challenge
            // verdict are recorded; the body itself is not, since an error
            // payload may echo account details.
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "(none)"
            let isChallenge = Self.isCloudflareChallenge(data: data, response: http)
            Self.logger.notice("""
                HTTP \(http.statusCode, privacy: .public) \
                content-type=\(contentType, privacy: .public) \
                bytes=\(data.count, privacy: .public) \
                cloudflareChallenge=\(isChallenge, privacy: .public)
                """)
        }

        switch http.statusCode {
        case 200:
            do {
                let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
                return UsageSnapshot(response: decoded)
            } catch {
                // A challenge page can arrive with a 200 as easily as a 403.
                if Self.isCloudflareChallenge(data: data, response: http) {
                    throw UsageError.cloudflareChallenge
                }
                Self.logger.error("Failed to decode usage response: \(error.localizedDescription, privacy: .public)")
                throw UsageError.malformedResponse
            }

        case 401:
            throw UsageError.sessionExpired

        case 403:
            // Three different situations arrive as 403 and need three
            // different responses from the user:
            //
            //   1. A Cloudflare challenge page  -> supply cf_clearance
            //   2. error_code account_session_invalid -> refresh sessionKey
            //   3. anything else -> the account genuinely lacks permission
            //
            // An expired session cookie is case 2, NOT 401 as one would
            // expect. Verified against the live endpoint.
            if Self.isCloudflareChallenge(data: data, response: http) {
                throw UsageError.cloudflareChallenge
            }
            if let apiError = APIErrorResponse.decoded(from: data) {
                if apiError.indicatesInvalidSession {
                    throw UsageError.sessionExpired
                }
                if let message = apiError.userFacingMessage {
                    throw UsageError.api(message: message)
                }
            }
            throw UsageError.insufficientPermissions

        case 404:
            throw UsageError.organizationNotFound

        case 429:
            throw UsageError.rateLimited(retryAfter: Self.retryAfter(from: http))

        case 503:
            throw Self.isCloudflareChallenge(data: data, response: http)
                ? UsageError.cloudflareChallenge
                : UsageError.server(status: 503)

        default:
            throw UsageError.server(status: http.statusCode)
        }
    }

    // MARK: - Private helpers

    private static func cookieHeader(sessionKey: String, cfClearance: String) -> String {
        var cookies = ["sessionKey=\(sessionKey.trimmingCharacters(in: .whitespacesAndNewlines))"]
        let clearance = cfClearance.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clearance.isEmpty {
            cookies.append("cf_clearance=\(clearance)")
        }
        return cookies.joined(separator: "; ")
    }

    private static func isCloudflareChallenge(data: Data, response: HTTPURLResponse) -> Bool {
        CloudflareChallengeDetector.isChallenge(
            body: data,
            contentType: response.value(forHTTPHeaderField: "Content-Type")
        )
    }

    /// Reads `Retry-After`, which may be either a delay in seconds or an
    /// HTTP-date.
    private static func retryAfter(from response: HTTPURLResponse) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }

        if let seconds = TimeInterval(raw) {
            return Date().addingTimeInterval(seconds)
        }
        return httpDate.date(from: raw)
    }

    private static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private static func mapped(_ error: URLError) -> UsageError {
        switch error.code {
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff:
            .offline
        default:
            .offline
        }
    }
}
