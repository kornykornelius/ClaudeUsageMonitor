import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL")  \(label)")
    if !condition { failures += 1 }
}

// MARK: - Cloudflare detection, against the page actually served to us

let capturedPath = CommandLine.arguments[1]
let challengeBody = try! Data(contentsOf: URL(fileURLWithPath: capturedPath))

check("real captured challenge page is detected",
      CloudflareChallengeDetector.isChallenge(body: challengeBody, contentType: "text/html; charset=UTF-8"))

check("same body is ignored when content type is JSON",
      !CloudflareChallengeDetector.isChallenge(body: challengeBody, contentType: "application/json"))

check("missing content type is not a challenge",
      !CloudflareChallengeDetector.isChallenge(body: challengeBody, contentType: nil))

let realJSON = Data(#"{"five_hour":{"utilization":42,"resets_at":"2026-08-22T18:30:00Z"}}"#.utf8)
check("genuine JSON body is not a challenge",
      !CloudflareChallengeDetector.isChallenge(body: realJSON, contentType: "application/json"))

check("HTML that is not a challenge is not flagged",
      !CloudflareChallengeDetector.isChallenge(body: Data("<html><body>hello</body></html>".utf8),
                                               contentType: "text/html"))

// A marker sitting past the inspected window must not be found.
let padding = String(repeating: " ", count: 9000)
check("marker beyond the 8KB window is not scanned",
      !CloudflareChallengeDetector.isChallenge(body: Data("<html>\(padding)just a moment</html>".utf8),
                                               contentType: "text/html"))

// MARK: - Percentage

check("0.42 fraction -> 42%", Percentage(apiValue: 0.42).value == 42)
check("42 whole -> 42%", Percentage(apiValue: 42).value == 42)
check("1.0 -> 100%", Percentage(apiValue: 1.0).value == 100)
check("0 -> 0%", Percentage(apiValue: 0).value == 0)
check("150 clamps to 100", Percentage(apiValue: 150).value == 100)
check("-5 clamps to 0", Percentage(apiValue: -5).value == 0)
check("NaN is 0, not a crash", Percentage(apiValue: .nan).value == 0)
check("infinity is 0, not a crash", Percentage(apiValue: .infinity).value == 0)
check("99.6 rounds to 100", Percentage(apiValue: 99.6).value == 100)

// The known ambiguity, asserted so the behaviour is pinned rather than accidental.
check("KNOWN LIMITATION: 0.8 is read as a fraction (80%), not 0.8%",
      Percentage(apiValue: 0.8).value == 80)

// MARK: - Snapshot construction

let full = Data(#"""
{"five_hour":{"utilization":0.42,"resets_at":"2026-08-22T18:30:00.000Z"},
 "seven_day":{"utilization":0.17,"resets_at":"2026-08-28T00:00:00Z"},
 "seven_day_opus":{"utilization":0.9,"resets_at":null},
 "extra_usage":{"is_available":true,"current_balance":12.5,"monthly_limit":50,"expires_at":"2026-09-01T00:00:00Z"}}
"""#.utf8)
let snapshot = UsageSnapshot(response: try! JSONDecoder().decode(UsageResponse.self, from: full))
check("only returned quotas appear (3, not 4)", snapshot.quotas.count == 3)
check("sonnet quota absent when omitted", !snapshot.quotas.contains { $0.kind == .sevenDaySonnet })
check("session group has 1 quota", snapshot.quotas(in: .session).count == 1)
check("weekly group has 2 quotas", snapshot.quotas(in: .weekly).count == 2)
check("fractional-seconds timestamp parses", snapshot.quotas.first { $0.kind == .fiveHour }?.resetsAt != nil)
check("plain timestamp parses", snapshot.quotas.first { $0.kind == .sevenDayAll }?.resetsAt != nil)
check("null timestamp is nil", snapshot.quotas.first { $0.kind == .sevenDayOpus }?.resetsAt == nil)
check("credits captured", snapshot.credits?.balance == 12.5)
check("snapshot is not empty", !snapshot.isEmpty)

// A free-plan style response: everything null.
let bare = Data(#"{"five_hour":null,"seven_day":null,"extra_usage":null}"#.utf8)
let bareSnapshot = UsageSnapshot(response: try! JSONDecoder().decode(UsageResponse.self, from: bare))
check("all-null response yields an EMPTY snapshot, not a crash", bareSnapshot.isEmpty)

// extra_usage present but unavailable must not produce a credits row.
let unavailable = Data(#"{"extra_usage":{"is_available":false,"current_balance":0}}"#.utf8)
let unavailableSnapshot = UsageSnapshot(response: try! JSONDecoder().decode(UsageResponse.self, from: unavailable))
check("is_available=false yields no credits", unavailableSnapshot.credits == nil)

// Unknown future fields must not break decoding.
let extraFields = Data(#"{"five_hour":{"utilization":0.5},"brand_new_field":{"x":1}}"#.utf8)
check("unknown fields do not break decoding",
      (try? JSONDecoder().decode(UsageResponse.self, from: extraFields)) != nil)

print("")

// MARK: - RefreshSchedule

print("")
check("no failures -> base 180s", RefreshSchedule.backoffDelay(consecutiveFailures: 0) == 180)
check("1st failure -> 360s (6min)", RefreshSchedule.backoffDelay(consecutiveFailures: 1) == 360)
check("2nd failure -> 720s (12min)", RefreshSchedule.backoffDelay(consecutiveFailures: 2) == 720)
check("3rd failure -> 1440s (24min)", RefreshSchedule.backoffDelay(consecutiveFailures: 3) == 1440)
check("4th failure -> capped 1800s (30min)", RefreshSchedule.backoffDelay(consecutiveFailures: 4) == 1800)
check("100th failure stays capped, no overflow", RefreshSchedule.backoffDelay(consecutiveFailures: 100) == 1800)
check("backoff never exceeds cap",
      (0...50).allSatisfy { RefreshSchedule.backoffDelay(consecutiveFailures: $0) <= 1800 })

let now = Date()
check("no reset known -> base", RefreshSchedule.successDelay(nextReset: nil, now: now) == 180)
check("reset far away -> base",
      RefreshSchedule.successDelay(nextReset: now.addingTimeInterval(9999), now: now) == 180)
check("reset in 60s -> wake at 65s (after it, not on it)",
      RefreshSchedule.successDelay(nextReset: now.addingTimeInterval(60), now: now) == 65)
check("reset 2s away -> floored at 30s, not a tight loop",
      RefreshSchedule.successDelay(nextReset: now.addingTimeInterval(2), now: now) == 30)
check("reset already past -> base",
      RefreshSchedule.successDelay(nextReset: now.addingTimeInterval(-100), now: now) == 180)
check("delay never below floor",
      (0...300).allSatisfy { RefreshSchedule.successDelay(nextReset: now.addingTimeInterval(Double($0)), now: now) >= 30 })

// MARK: - APIErrorResponse, against the real captured body

let realError = Data(#"{"type":"error","error":{"type":"permission_error","message":"Invalid authorization","details":{"error_code":"account_session_invalid","error_visibility":"user_facing"}},"request_id":null}"#.utf8)
let parsed = APIErrorResponse.decoded(from: realError)
check("real 403 body decodes", parsed != nil)
check("real 403 is recognised as an invalid session", parsed?.indicatesInvalidSession == true)
check("server message surfaced", parsed?.userFacingMessage == "Invalid authorization")

let permError = Data(#"{"type":"error","error":{"type":"permission_error","message":"You do not have access","details":{"error_code":"forbidden"}}}"#.utf8)
let permParsed = APIErrorResponse.decoded(from: permError)
check("a genuine permission error is NOT treated as an expired session",
      permParsed?.indicatesInvalidSession == false)
check("its message is surfaced", permParsed?.userFacingMessage == "You do not have access")

check("HTML body does not decode as an API error",
      APIErrorResponse.decoded(from: Data("<html>nope</html>".utf8)) == nil)
check("empty JSON object decodes with no error code",
      APIErrorResponse.decoded(from: Data("{}".utf8))?.indicatesInvalidSession == false)

print("")
print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
