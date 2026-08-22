import SwiftUI
import Combine

// MARK: - Menu Bar Popover Content
struct PopoverView: View {
    @Bindable var manager: UsageViewModel

    /// Beyond this the content scrolls rather than growing a taller panel.
    private static let maximumHeight: CGFloat = 560
    private static let width: CGFloat = 300

    @State private var showCredentials = false
    /// Drives the "updated 2 min ago" line without waiting for a refresh.
    @State private var now = Date()

    private let clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    /// The panel sizes itself to its content, up to `maximumHeight`.
    ///
    /// The previous implementation hard-coded a height, which left a large
    /// empty area for accounts reporting only one or two quotas. A
    /// `ScrollView` reports its content's ideal size as its own, so capping it
    /// with `maxHeight` is enough: short content yields a short panel, and only
    /// content past the cap starts scrolling. Measuring the content with a
    /// `GeometryReader` and feeding that back into the frame would be circular,
    /// and collapses to zero height before the first layout pass.
    var body: some View {
        ScrollView {
            PopoverContent(
                manager: manager,
                showCredentials: $showCredentials,
                now: now,
                width: Self.width
            )
        }
        .frame(width: Self.width)
        .frame(maxHeight: Self.maximumHeight)
        .onReceive(clock) { now = $0 }
        .task {
            showCredentials = !manager.hasCredentials
            await manager.refreshIfStale()
        }
    }
}

/// Everything inside the popover's scroll area.
///
/// Split from `PopoverView` so the content can be laid out and drawn without
/// the scroll view around it — `ImageRenderer` lays `ScrollView` content out
/// but does not draw it, which makes offscreen snapshots of each state
/// impossible while the two are fused.
struct PopoverContent: View {
    @Bindable var manager: UsageViewModel
    @Binding var showCredentials: Bool
    var now: Date
    var width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            credentialsSection
            footer
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "brain.head.profile")
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            if manager.state.isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .needsSetup:
            message("Enter your sessionKey and Organization ID below to get started.")

        case .loading:
            message("Loading…")

        case .loaded(let snapshot, _), .refreshing(let snapshot, _):
            if snapshot.isEmpty {
                message("claude.ai returned no quota data for this account. Plans differ in which quotas they report.")
            } else {
                snapshotBody(snapshot)
            }

        case .failed(let error):
            errorBody(error)
        }
    }

    @ViewBuilder
    private func snapshotBody(_ snapshot: UsageSnapshot) -> some View {
        let groups = QuotaGroup.allCases.filter { !snapshot.quotas(in: $0).isEmpty }

        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            if let heading = group.heading {
                Text(heading)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }

            ForEach(snapshot.quotas(in: group)) { quota in
                QuotaSectionView(quota: quota)
            }

            // Separate groups from one another, but do not leave a trailing
            // rule butting up against the divider below.
            if index < groups.count - 1 || snapshot.credits != nil {
                Divider()
            }
        }

        if let credits = snapshot.credits {
            creditsBody(credits)
        }
    }

    private func creditsBody(_ credits: UsageSnapshot.Credits) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extra Usage Credits")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            LabeledRow("Current Balance", value: credits.balance.formatted(.currency(code: "USD")), emphasised: true)
            LabeledRow("Monthly Spend Cap", value: credits.monthlyCap.formatted(.currency(code: "USD")))
            LabeledRow("Expires", value: Timestamp.medium(credits.expiresAt))
        }
    }

    private func errorBody(_ error: UsageError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Text(error.recoverySuggestion)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !error.isTransient {
                Text("Automatic refresh is paused until you change a credential or press Refresh.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Credentials

    private var credentialsSection: some View {
        DisclosureGroup(isExpanded: $showCredentials) {
            CredentialsView(
                sessionKey: $manager.sessionKey,
                cfClearance: $manager.cfClearance,
                orgId: $manager.orgId
            )
            .padding(.top, 6)
        } label: {
            Text("Credentials")
                .font(.caption)
                .bold()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = freshnessLine {
                Text(line)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Refresh") { manager.refreshNow() }
                    .disabled(manager.state.isBusy)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    /// "Updated 2 min ago · next in 3 min". Omitted entirely before the first
    /// successful fetch, where it would say nothing useful.
    private var freshnessLine: String? {
        let fetchedAt: Date
        switch manager.state {
        case .loaded(_, let at), .refreshing(_, let at): fetchedAt = at
        case .needsSetup, .loading, .failed: return nil
        }

        var line = "Updated \(Timestamp.relative(fetchedAt, to: now))"
        if let next = manager.nextRefreshAt, next > now {
            line += " · next \(Timestamp.relative(next, to: now))"
        }
        return line
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.secondary)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A label on the left, a value on the right — the shape every credits row uses.
private struct LabeledRow: View {
    let label: String
    let value: String
    var emphasised = false

    init(_ label: String, value: String, emphasised: Bool = false) {
        self.label = label
        self.value = value
        self.emphasised = emphasised
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).bold(emphasised)
        }
        .font(emphasised ? .subheadline : .caption)
        .foregroundColor(emphasised ? .primary : .secondary)
    }
}

// MARK: - Previews

private extension UsageSnapshot {
    /// A Max-style account reporting every quota plus credits.
    static var richSample: UsageSnapshot {
        UsageSnapshot(
            quotas: [
                .init(kind: .fiveHour, percentage: Percentage(apiValue: 0.42),
                      resetsAt: Date().addingTimeInterval(3 * 3600)),
                .init(kind: .sevenDayAll, percentage: Percentage(apiValue: 0.17),
                      resetsAt: Date().addingTimeInterval(4 * 86400)),
                .init(kind: .sevenDaySonnet, percentage: Percentage(apiValue: 0.66),
                      resetsAt: Date().addingTimeInterval(4 * 86400)),
                .init(kind: .sevenDayOpus, percentage: Percentage(apiValue: 0.91),
                      resetsAt: Date().addingTimeInterval(4 * 86400)),
            ],
            credits: .init(balance: 12.5, monthlyCap: 50, expiresAt: Date().addingTimeInterval(9 * 86400))
        )
    }

    /// A Free/Pro-style account reporting only the session window.
    static var sparseSample: UsageSnapshot {
        UsageSnapshot(
            quotas: [
                .init(kind: .fiveHour, percentage: Percentage(apiValue: 0.08),
                      resetsAt: Date().addingTimeInterval(1800)),
            ],
            credits: nil
        )
    }

    static var emptySample: UsageSnapshot {
        UsageSnapshot(quotas: [], credits: nil)
    }
}

#Preview("Loaded — all quotas") {
    PopoverView(manager: .preview(.loaded(.richSample, fetchedAt: Date().addingTimeInterval(-120)),
                                  nextRefreshAt: Date().addingTimeInterval(60)))
}

#Preview("Loaded — sparse plan") {
    PopoverView(manager: .preview(.loaded(.sparseSample, fetchedAt: Date().addingTimeInterval(-30))))
}

#Preview("Loaded — no quota data") {
    PopoverView(manager: .preview(.loaded(.emptySample, fetchedAt: Date())))
}

#Preview("Needs setup") {
    PopoverView(manager: .preview(.needsSetup, sessionKey: "", orgId: ""))
}

#Preview("Session expired") {
    PopoverView(manager: .preview(.failed(.sessionExpired)))
}

#Preview("Cloudflare challenge") {
    PopoverView(manager: .preview(.failed(.cloudflareChallenge)))
}

#Preview("Offline (transient)") {
    PopoverView(manager: .preview(.failed(.offline)))
}
