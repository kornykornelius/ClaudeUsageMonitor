import SwiftUI

// MARK: - Menu Bar Popover Content
struct PopoverView: View {
    @ObservedObject var manager: ClaudeUsageManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Header
                HStack {
                    Image(systemName: "brain.head.profile")
                    Text("Claude Usage Dashboard")
                        .font(.headline)
                    Spacer()
                    if manager.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }

                Divider()

                if let usage = manager.usageData {

                    // 1. Current 5-Hour Session Window
                    if let fiveHour = usage.fiveHour {
                        QuotaSectionView(
                            title: "Current 5-Hour Session",
                            rawUtilization: fiveHour.utilization,
                            resetTime: fiveHour.formattedResetTime
                        )
                    }

                    Divider()

                    // 2. Weekly Quotas (7-Day Limits)
                    Text("Weekly Quotas (7-Day Limits)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    if let sevenDay = usage.sevenDay {
                        QuotaSectionView(
                            title: "All Models Total",
                            rawUtilization: sevenDay.utilization,
                            resetTime: sevenDay.formattedResetTime
                        )
                    }

                    if let sonnet = usage.sevenDaySonnet {
                        QuotaSectionView(
                            title: "Sonnet Specific",
                            rawUtilization: sonnet.utilization,
                            resetTime: sonnet.formattedResetTime
                        )
                    }

                    if let opus = usage.sevenDayOpus {
                        QuotaSectionView(
                            title: "Opus Specific",
                            rawUtilization: opus.utilization,
                            resetTime: opus.formattedResetTime
                        )
                    }

                    Divider()

                    // 3. Usage Credits & Monthly Limits
                    if let credit = usage.extraUsage, credit.isAvailable == true {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Extra Usage Credits")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)

                            HStack {
                                Text("Current Balance:")
                                Spacer()
                                Text("$\(credit.currentBalance ?? 0.0, specifier: "%.2f")")
                                    .bold()
                            }
                            .font(.subheadline)

                            HStack {
                                Text("Monthly Spend Cap:")
                                Spacer()
                                Text("$\(credit.monthlyLimit ?? 0.0, specifier: "%.2f")")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            HStack {
                                Text("Expires:")
                                Spacer()
                                Text(credit.formattedExpiration)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }

                } else {
                    Text(manager.statusText)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }

                Divider()

                // Configuration Settings
                CredentialsView(
                    sessionKey: $manager.sessionKey,
                    orgId: $manager.orgId
                )

                HStack {
                    Button("Refresh") {
                        Task { await manager.fetchUsage() }
                    }
                    Spacer()
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 300, height: 460)
        .onAppear {
            Task { await manager.fetchUsage() }
        }
    }
}
