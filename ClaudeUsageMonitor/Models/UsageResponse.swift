import Foundation

// MARK: - API Response Models
struct UsageResponse: Codable {
    let fiveHour: LimitDetail?
    let sevenDay: LimitDetail?
    let sevenDaySonnet: LimitDetail?
    let sevenDayOpus: LimitDetail?
    let extraUsage: ExtraUsageDetail?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
    }
}

struct LimitDetail: Codable {
    let utilization: Double // API value (0.0 to 1.0 or 0 to 100)
    let resetsAt: String?   // ISO timestamp

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var formattedResetTime: String {
        guard let resetsAt = resetsAt else { return "N/A" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        displayFormatter.timeStyle = .short

        if let date = formatter.date(from: resetsAt) ?? ISO8601DateFormatter().date(from: resetsAt) {
            return displayFormatter.string(from: date)
        }
        return resetsAt
    }
}

struct ExtraUsageDetail: Codable {
    let isAvailable: Bool?
    let currentBalance: Double?
    let monthlyLimit: Double?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case currentBalance = "current_balance"
        case monthlyLimit = "monthly_limit"
        case expiresAt = "expires_at"
    }

    var formattedExpiration: String {
        guard let expiresAt = expiresAt else { return "N/A" }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: expiresAt) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return expiresAt
    }
}
