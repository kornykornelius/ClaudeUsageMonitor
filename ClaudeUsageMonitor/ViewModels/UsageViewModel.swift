import Foundation
import Observation
import os

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

    /// When the next automatic refresh is due, for display in the popover.
    private(set) var nextRefreshAt: Date?

    /// claude.ai session cookie. Written straight through to the Keychain.
    var sessionKey: String {
        didSet {
            credentials.setValue(sessionKey, for: .sessionKey)
            credentialsDidChange()
        }
    }

    /// Cloudflare clearance cookie. Optional; sent alongside the session key
    /// when present.
    var cfClearance: String {
        didSet {
            credentials.setValue(cfClearance, for: .cfClearance)
            credentialsDidChange()
        }
    }

    /// Organisation UUID. Not a secret — it appears in every claude.ai API URL —
    /// so UserDefaults is an appropriate home for it.
    var orgId: String {
        didSet {
            defaults.set(orgId, forKey: Self.orgIdDefaultsKey)
            credentialsDidChange()
        }
    }

    // MARK: - Scheduling constants

    /// Opening the popover refetches only if the data is older than this.
    static let stalenessThreshold: TimeInterval = 30
    /// How long to wait after the last keystroke in a credential field before
    /// acting on it.
    static let credentialDebounce: Duration = .milliseconds(1200)

    private static let orgIdDefaultsKey = "orgId"
    private static let logger = Logger(subsystem: "woeichwan.ClaudeUsageMonitor", category: "UsageViewModel")

    private let credentials: CredentialStore
    private let defaults: UserDefaults
    private let client: UsageAPIClient

    private var pollingTask: Task<Void, Never>?
    private var credentialDebounceTask: Task<Void, Never>?
    private var isFetching = false
    private var consecutiveFailures = 0

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

        // Assigning in init does not fire didSet, so this load neither writes
        // the values straight back out nor triggers the debounce.
        self.sessionKey = credentials.value(for: .sessionKey)
        self.cfClearance = credentials.value(for: .cfClearance)
        self.orgId = defaults.string(forKey: Self.orgIdDefaultsKey) ?? ""

        startPolling()
    }

    var hasCredentials: Bool {
        !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !orgId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Builds a view model pinned to a given state, touching neither the
    /// Keychain nor the network and never starting the poll loop.
    ///
    /// Exists so each popover state can be rendered — in Xcode previews and in
    /// offscreen snapshots — without a live account. States such as "Cloudflare
    /// is challenging you" or "this plan reports no Opus quota" are otherwise
    /// close to impossible to reach deliberately.
    static func preview(
        _ state: LoadState,
        sessionKey: String = "sk-ant-sid01-preview",
        orgId: String = "00000000-0000-4000-8000-000000000000",
        nextRefreshAt: Date? = nil
    ) -> UsageViewModel {
        let model = UsageViewModel(previewing: state, sessionKey: sessionKey, orgId: orgId)
        model.nextRefreshAt = nextRefreshAt
        return model
    }

    private init(previewing state: LoadState, sessionKey: String, orgId: String) {
        // An isolated defaults suite so a preview cannot disturb real settings.
        self.credentials = CredentialStore(service: "preview.ClaudeUsageMonitor",
                                           defaults: UserDefaults(suiteName: "preview.ClaudeUsageMonitor") ?? .standard)
        self.defaults = UserDefaults(suiteName: "preview.ClaudeUsageMonitor") ?? .standard
        self.client = UsageAPIClient()
        self.sessionKey = sessionKey
        self.cfClearance = ""
        self.orgId = orgId
        self.state = state
        // Deliberately no startPolling().
    }

    // MARK: - Polling

    /// Starts (or restarts) the refresh loop, fetching immediately.
    ///
    /// This replaces a `Timer` scheduled on the default run-loop mode, which
    /// stopped firing while a menu was being tracked and only ever fired at a
    /// fixed 180s regardless of whether requests were succeeding. It also fixes
    /// the app never fetching at launch: the old code only refreshed from the
    /// popover's `onAppear`, so the menu bar read "Claude" until either the
    /// popover was opened or three minutes elapsed.
    func startPolling() {
        pollingTask?.cancel()
        consecutiveFailures = 0
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await fetchUsage()

            guard let delay = nextDelay() else {
                // Nothing a retry could fix. Sit idle until the credentials
                // change or the user asks for a refresh.
                nextRefreshAt = nil
                return
            }

            nextRefreshAt = Date().addingTimeInterval(delay)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return // cancelled
            }
        }
    }

    /// How long to wait before the next attempt, or `nil` to stop polling.
    private func nextDelay() -> TimeInterval? {
        switch state {
        case .needsSetup:
            // No credentials: polling would just re-derive the same state.
            return nil

        case .loaded(let snapshot, _), .refreshing(let snapshot, _):
            consecutiveFailures = 0
            return successDelay(for: snapshot)

        case .loading:
            return RefreshSchedule.base

        case .failed(let error) where error.isTransient:
            consecutiveFailures += 1
            let delay = RefreshSchedule.backoffDelay(consecutiveFailures: consecutiveFailures)
            Self.logger.notice("Transient failure #\(self.consecutiveFailures) (\(error.title, privacy: .public)); next attempt in \(Int(delay))s")
            return delay

        case .failed(let error):
            // A bad organisation ID or an expired session will fail identically
            // forever. Retrying on a timer only hammers Cloudflare and burns
            // battery; the user has to change something first.
            Self.logger.notice("Non-recoverable failure (\(error.title, privacy: .public)); pausing automatic refresh")
            return nil
        }
    }

    private func successDelay(for snapshot: UsageSnapshot) -> TimeInterval {
        let now = Date()
        let nextReset = snapshot.quotas
            .compactMap(\.resetsAt)
            .filter { $0 > now }
            .min()
        return RefreshSchedule.successDelay(nextReset: nextReset, now: now)
    }

    // MARK: - Fetching

    /// Refetches unconditionally. Used by the Refresh button and the poll loop.
    func fetchUsage() async {
        guard hasCredentials else {
            state = .needsSetup
            return
        }

        // The Refresh button and the poll loop can both fire at once.
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

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

    /// Called when the popover opens. Avoids a request per open when the data
    /// on screen is already current.
    func refreshIfStale() async {
        switch state {
        case .loaded(_, let fetchedAt) where Date().timeIntervalSince(fetchedAt) < Self.stalenessThreshold:
            return
        case .refreshing:
            return // already in flight
        default:
            break
        }

        // Restart rather than a bare fetch, so the automatic cadence realigns
        // with this manual refresh instead of firing again moments later.
        startPolling()
    }

    /// Manual refresh from the popover button. Always refetches, and resumes
    /// polling if a non-recoverable failure had paused it.
    func refreshNow() {
        startPolling()
    }

    // MARK: - Credential changes

    /// Credential fields fire `didSet` on every keystroke. Restarting the poll
    /// loop each time would issue a request per character, so the restart is
    /// debounced. The Keychain write is not debounced — it is cheap, and losing
    /// the last keystroke to a quit would be worse.
    private func credentialsDidChange() {
        credentialDebounceTask?.cancel()
        credentialDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.credentialDebounce)
            guard !Task.isCancelled else { return }
            self?.startPolling()
        }
    }
}
