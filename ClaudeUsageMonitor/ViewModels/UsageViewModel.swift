import Foundation
import Observation

/// Owns the usage data shown in the menu bar popover and the credentials used
/// to fetch it.
///
/// Credentials are deliberately *not* held in `@AppStorage`. A property wrapper
/// declared inside an observable class does not participate in that class's
/// change tracking, which made previous edits fail to propagate; and
/// `@AppStorage` can only write to UserDefaults, which is the wrong home for a
/// credential that grants full account access. Secrets go to the Keychain via
/// `CredentialStore`; only the non-secret organisation ID stays in UserDefaults.
@MainActor
@Observable
final class UsageViewModel {
    private(set) var usageData: UsageResponse?
    private(set) var statusText: String = "Loading..."
    private(set) var isLoading: Bool = false

    /// claude.ai session cookie. Written straight through to the Keychain.
    var sessionKey: String {
        didSet { credentials.setValue(sessionKey, for: .sessionKey) }
    }

    /// Cloudflare clearance cookie. Optional; sent alongside the session key
    /// when present.
    var cfClearance: String {
        didSet { credentials.setValue(cfClearance, for: .cfClearance) }
    }

    /// Organisation UUID. Not a secret — it appears in every claude.ai API URL —
    /// so UserDefaults is an appropriate home for it.
    var orgId: String {
        didSet { defaults.set(orgId, forKey: Self.orgIdDefaultsKey) }
    }

    private static let orgIdDefaultsKey = "orgId"

    private let credentials: CredentialStore
    private let defaults: UserDefaults
    private var timer: Timer?

    init(credentials: CredentialStore = CredentialStore(), defaults: UserDefaults = .standard) {
        self.credentials = credentials
        self.defaults = defaults

        // Runs before the credentials are read below, so a value migrated out
        // of UserDefaults on this launch is picked up immediately.
        credentials.migrateLegacyPlaintextCredentials()

        // Assigning in init does not fire didSet, so this load does not write
        // the values straight back out again.
        self.sessionKey = credentials.value(for: .sessionKey)
        self.cfClearance = credentials.value(for: .cfClearance)
        self.orgId = defaults.string(forKey: Self.orgIdDefaultsKey) ?? ""

        startTimer()
    }

    func startTimer() {
        timer?.invalidate()
        // Automatically fetches updates every 3 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { await self?.fetchUsage() }
        }
    }

    func fetchUsage() async {
        let cleanKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOrg = orgId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanClearance = cfClearance.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanKey.isEmpty, !cleanOrg.isEmpty else {
            self.statusText = "Setup Required"
            return
        }

        guard let url = URL(string: "https://claude.ai/api/organizations/\(cleanOrg)/usage") else {
            self.statusText = "Invalid URL / Org ID"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        // Full browser headers to pass Cloudflare checks
        var cookies = ["sessionKey=\(cleanKey)"]
        if !cleanClearance.isEmpty {
            cookies.append("cf_clearance=\(cleanClearance)")
        }
        request.setValue(cookies.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")

        self.isLoading = true

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            self.isLoading = false

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    self.usageData = try decoder.decode(UsageResponse.self, from: data)
                    self.statusText = "Updated"
                } else {
                    self.statusText = "HTTP Error \(httpResponse.statusCode) (Check Credentials)"
                }
            }
        } catch {
            self.isLoading = false
            self.statusText = "Network Error: \(error.localizedDescription)"
        }
    }
}
