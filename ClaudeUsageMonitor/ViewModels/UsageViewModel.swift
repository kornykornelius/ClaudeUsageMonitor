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
    /// The single source of truth for what the popover shows.
    private(set) var state: LoadState = .needsSetup

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
    private let client: UsageAPIClient
    private var timer: Timer?

    init(
        credentials: CredentialStore = CredentialStore(),
        defaults: UserDefaults = .standard,
        client: UsageAPIClient = UsageAPIClient()
    ) {
        self.credentials = credentials
        self.defaults = defaults
        self.client = client

        // Runs before the credentials are read below, so a value migrated out
        // of UserDefaults on this launch is picked up immediately.
        credentials.migrateLegacyPlaintextCredentials()

        // Assigning in init does not fire didSet, so this load does not write
        // the values straight back out again.
        self.sessionKey = credentials.value(for: .sessionKey)
        self.cfClearance = credentials.value(for: .cfClearance)
        self.orgId = defaults.string(forKey: Self.orgIdDefaultsKey) ?? ""

        if !hasCredentials {
            self.state = .needsSetup
        }

        startTimer()
    }

    var hasCredentials: Bool {
        !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !orgId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func startTimer() {
        timer?.invalidate()
        // Automatically fetches updates every 3 minutes.
        // Phase 4 replaces this with a Task-based loop that survives menu
        // tracking and backs off when requests fail.
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { await self?.fetchUsage() }
        }
    }

    func fetchUsage() async {
        guard hasCredentials else {
            state = .needsSetup
            return
        }

        // Keep showing the previous snapshot while refreshing, so the popover
        // does not blank out on every poll.
        if let existing = state.snapshot {
            state = .refreshing(existing, fetchedAt: Date())
        } else {
            state = .loading
        }

        do {
            let snapshot = try await client.fetchUsage(
                orgId: orgId,
                sessionKey: sessionKey,
                cfClearance: cfClearance
            )
            state = .loaded(snapshot, fetchedAt: Date())
        } catch let error as UsageError {
            state = .failed(error)
        } catch {
            state = .failed(.malformedResponse)
        }
    }
}
