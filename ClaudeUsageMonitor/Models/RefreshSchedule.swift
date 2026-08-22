import Foundation

/// Decides how long to wait before the next refresh.
///
/// Pure arithmetic, deliberately separated from the view model so the cadence
/// can be checked directly instead of inferred from timing a running app.
enum RefreshSchedule {
    /// Normal poll interval on success.
    static let base: TimeInterval = 180
    /// Ceiling for backoff, so a long outage settles at one request per half hour.
    static let maximum: TimeInterval = 1800
    /// Floor for any scheduled wake, so a reset landing seconds away cannot
    /// turn into a tight loop.
    static let minimum: TimeInterval = 30

    /// Exponential backoff after repeated transient failures.
    ///
    /// `1 -> 6min, 2 -> 12min, 3 -> 24min, 4+ -> 30min (capped)`. The point is
    /// to stop a dead session or an outage from generating 480 identical
    /// requests a day.
    static func backoffDelay(consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return base }
        // Cap the exponent before it reaches pow()'s dynamic range.
        let exponent = Double(min(consecutiveFailures, 16))
        return min(base * pow(2, exponent), maximum)
    }

    /// Normally the base interval, but wakes earlier when a quota is about to
    /// reset so the display updates promptly rather than up to three minutes
    /// late.
    ///
    /// - Parameter nextReset: the soonest future reset among the quotas on
    ///   screen, or `nil` if none is known.
    static func successDelay(nextReset: Date?, now: Date = Date()) -> TimeInterval {
        guard let nextReset, nextReset > now else { return base }
        // A small buffer so the request lands after the reset, not on it.
        let untilReset = nextReset.timeIntervalSince(now) + 5
        return max(minimum, min(base, untilReset))
    }
}
