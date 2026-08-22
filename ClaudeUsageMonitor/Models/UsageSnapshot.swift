import Foundation

// MARK: - Percentage

/// A quota utilisation expressed as whole percent, always in `0...100`.
///
/// - Important: The claude.ai endpoint is undocumented and the magnitude of
///   `utilization` has not been confirmed against a captured response. Some
///   deployments report a `0.0...1.0` fraction, others a `0...100` number. The
///   rule below guesses from the magnitude, which is wrong in one specific
///   case: a genuine reading below 1% is indistinguishable from a fraction and
///   will be shown 100× too large (0.8% renders as 80%).
///
///   This is the single place that rule lives. Once a real response has been
///   captured, replace the body of `init(apiValue:)` with the correct
///   conversion and delete this note — nothing else needs to change.
struct Percentage: Equatable, Comparable {
    /// Whole percent, clamped to `0...100`.
    let value: Int

    init(apiValue: Double) {
        guard apiValue.isFinite else {
            self.value = 0
            return
        }
        let percent = apiValue <= 1.0 ? apiValue * 100 : apiValue
        self.value = min(max(Int(percent.rounded()), 0), 100)
    }

    static func < (lhs: Percentage, rhs: Percentage) -> Bool { lhs.value < rhs.value }
}

// MARK: - Quota identity

/// Which quota a row describes. Also carries its display name and grouping, so
/// views never hard-code either.
enum QuotaKind: String, CaseIterable, Identifiable {
    case fiveHour
    case sevenDayAll
    case sevenDaySonnet
    case sevenDayOpus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour: "Current 5-Hour Session"
        case .sevenDayAll: "All Models Total"
        case .sevenDaySonnet: "Sonnet Specific"
        case .sevenDayOpus: "Opus Specific"
        }
    }

    var group: QuotaGroup {
        switch self {
        case .fiveHour: .session
        case .sevenDayAll, .sevenDaySonnet, .sevenDayOpus: .weekly
        }
    }
}

enum QuotaGroup: String, CaseIterable, Identifiable {
    case session
    case weekly

    var id: String { rawValue }

    /// Section heading, or `nil` when the group needs no heading of its own.
    var heading: String? {
        switch self {
        case .session: nil
        case .weekly: "Weekly Quotas (7-Day Limits)"
        }
    }
}

// MARK: - Snapshot

/// The usage picture at one point in time, in the shape the UI actually needs.
///
/// Only quotas the API returned are present. Which ones appear varies by plan,
/// so a missing entry means "this account does not report that quota", not an
/// error.
struct UsageSnapshot: Equatable {
    struct Quota: Equatable, Identifiable {
        let kind: QuotaKind
        let percentage: Percentage
        let resetsAt: Date?

        var id: String { kind.id }
    }

    struct Credits: Equatable {
        let balance: Double
        let monthlyCap: Double
        let expiresAt: Date?
    }

    let quotas: [Quota]
    let credits: Credits?

    /// True when the request succeeded but the account reported no quota data
    /// at all — distinct from a failure, and worth saying out loud in the UI.
    var isEmpty: Bool { quotas.isEmpty && credits == nil }

    func quotas(in group: QuotaGroup) -> [Quota] {
        quotas.filter { $0.kind.group == group }
    }
}

// MARK: - Building a snapshot from the wire format

extension UsageSnapshot {
    init(response: UsageResponse) {
        let candidates: [(QuotaKind, LimitDetail?)] = [
            (.fiveHour, response.fiveHour),
            (.sevenDayAll, response.sevenDay),
            (.sevenDaySonnet, response.sevenDaySonnet),
            (.sevenDayOpus, response.sevenDayOpus),
        ]

        self.quotas = candidates.compactMap { kind, detail in
            guard let detail else { return nil }
            return Quota(
                kind: kind,
                percentage: Percentage(apiValue: detail.utilization),
                resetsAt: Timestamp.date(from: detail.resetsAt)
            )
        }

        if let extra = response.extraUsage, extra.isAvailable == true {
            self.credits = Credits(
                balance: extra.currentBalance ?? 0,
                monthlyCap: extra.monthlyLimit ?? 0,
                expiresAt: Timestamp.date(from: extra.expiresAt)
            )
        } else {
            self.credits = nil
        }
    }
}

// MARK: - Timestamps

/// Date parsing and display formatting.
///
/// The formatters are `static let` because `DateFormatter` and
/// `ISO8601DateFormatter` are expensive to build, and the previous
/// implementation constructed up to three of them every time a row rendered.
enum Timestamp {
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()

    private static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Parses an ISO-8601 timestamp, with or without fractional seconds.
    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return iso8601WithFractionalSeconds.date(from: string) ?? iso8601.date(from: string)
    }

    static func short(_ date: Date?) -> String {
        guard let date else { return "N/A" }
        return shortDateTime.string(from: date)
    }

    static func medium(_ date: Date?) -> String {
        guard let date else { return "N/A" }
        return mediumDateTime.string(from: date)
    }
}
