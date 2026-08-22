import SwiftUI
import Combine

// MARK: - Menu Bar Popover Content
struct PopoverView: View {
    @Bindable var manager: UsageViewModel

    /// Beyond this the content scrolls rather than growing a taller panel.
    private static let maximumHeight: CGFloat = 560
    private static let width: CGFloat = 300
    /// Used for the single layout pass before the content has been measured.
    /// Roughly a loaded popover; any error is corrected on the next pass.
    private static let unmeasuredHeight: CGFloat = 240

    @State private var showCredentials = false
    /// Drives the "updated 2 min ago" line without waiting for a refresh.
    @State private var now = Date()
    /// The content's ideal height, measured inside the scroll view.
    @State private var contentHeight: CGFloat = 0

    private let clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    /// The panel sizes itself to its content, up to `maximumHeight`.
    ///
    /// `MenuBarExtra(.window)` sizes its panel by proposing `nil` height and
    /// taking whatever the content calls ideal. A `ScrollView` answers that
    /// proposal with a fixed 10pt — it does *not* pass its content's ideal
    /// height through — so `.frame(maxHeight:)` alone clamps a number that
    /// never arrives and the panel renders as a 300x10 sliver. An earlier
    /// version shipped exactly that. It was invisible to
    /// `Tools/render-snapshots.sh` because `ImageRenderer` proposes a concrete
    /// size, so the failing path was never exercised.
    ///
    /// So the height is measured and applied explicitly. This is not the
    /// circular measurement that collapsed to 1pt during the refactor: that one
    /// fed a `GeometryReader` reading of a view back into *that same view's*
    /// frame. Here the reading is taken from the content *inside* the scroll
    /// view, where the vertical proposal is unbounded, and applied to the
    /// scroll view *around* it. The measurement therefore does not depend on
    /// the frame it sets, and settles in one pass.
    var body: some View {
        ScrollView {
            PopoverContent(
                manager: manager,
                showCredentials: $showCredentials,
                now: now,
                width: Self.width
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .frame(width: Self.width, height: panelHeight)
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .onReceive(clock) { now = $0 }
        .task {
            showCredentials = !manager.hasCredentials
            await manager.refreshIfStale()
        }
    }

    private var panelHeight: CGFloat {
        guard contentHeight > 0 else { return Self.unmeasuredHeight }
        return min(contentHeight, Self.maximumHeight)
    }
}

/// Carries the measured height of the popover's content out to the scroll view
/// that wraps it.
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
