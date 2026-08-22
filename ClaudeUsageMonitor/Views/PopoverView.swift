import SwiftUI

// MARK: - Menu Bar Popover Content
struct PopoverView: View {
    @Bindable var manager: UsageViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                Divider()

                content

                Divider()

                CredentialsView(
                    sessionKey: $manager.sessionKey,
                    cfClearance: $manager.cfClearance,
                    orgId: $manager.orgId
                )

                HStack {
                    Button("Refresh") {
                        manager.refreshNow()
                    }
                    Spacer()
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 300, height: 500)
        .task {
            await manager.refreshIfStale()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "brain.head.profile")
            Text("Claude Usage Dashboard")
                .font(.headline)
            Spacer()
            if manager.state.isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .needsSetup:
            statusText("Enter your sessionKey and Organization ID below to get started.")

        case .loading:
            statusText("Loading…")

        case .loaded(let snapshot, _), .refreshing(let snapshot, _):
            if snapshot.isEmpty {
                statusText("No quota data was returned for this account.")
            } else {
                snapshotBody(snapshot)
            }

        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Text(error.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                Text(error.recoverySuggestion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func snapshotBody(_ snapshot: UsageSnapshot) -> some View {
        ForEach(QuotaGroup.allCases) { group in
            let quotas = snapshot.quotas(in: group)
            if !quotas.isEmpty {
                if let heading = group.heading {
                    Text(heading)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                ForEach(quotas) { quota in
                    QuotaSectionView(quota: quota)
                }
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

            HStack {
                Text("Current Balance:")
                Spacer()
                Text(credits.balance, format: .currency(code: "USD"))
                    .bold()
            }
            .font(.subheadline)

            HStack {
                Text("Monthly Spend Cap:")
                Spacer()
                Text(credits.monthlyCap, format: .currency(code: "USD"))
            }
            .font(.caption)
            .foregroundColor(.secondary)

            HStack {
                Text("Expires:")
                Spacer()
                Text(Timestamp.medium(credits.expiresAt))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func statusText(_ message: String) -> some View {
        Text(message)
            .foregroundColor(.secondary)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }
}
