import Foundation

/// Representative snapshots for Xcode previews and offscreen snapshot tests.
///
/// These are not test fixtures in the usual sense — they exist because the
/// interesting states of this app are the ones that are hard to reach on
/// purpose. Rendering "a plan that reports no Opus quota" or "an account with
/// no quota data at all" against a live account is a matter of luck; against
/// these it is deterministic.
extension UsageSnapshot {
    /// A Max-style account reporting every quota, plus extra usage credits.
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
            credits: .init(balance: 12.5, monthlyCap: 50,
                           expiresAt: Date().addingTimeInterval(9 * 86400))
        )
    }

    /// A Free/Pro-style account reporting only the rolling session window.
    static var sparseSample: UsageSnapshot {
        UsageSnapshot(
            quotas: [
                .init(kind: .fiveHour, percentage: Percentage(apiValue: 0.08),
                      resetsAt: Date().addingTimeInterval(1800)),
            ],
            credits: nil
        )
    }

    /// A successful response that carried no quota data at all.
    static var emptySample: UsageSnapshot {
        UsageSnapshot(quotas: [], credits: nil)
    }
}
