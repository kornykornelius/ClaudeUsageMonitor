import Foundation

/// The structured error body claude.ai returns alongside a non-success status.
///
/// Captured shape, for an invalid session cookie:
///
/// ```json
/// {"type":"error",
///  "error":{"type":"permission_error",
///           "message":"Invalid authorization",
///           "details":{"error_code":"account_session_invalid",
///                      "error_visibility":"user_facing"}},
///  "request_id":null}
/// ```
///
/// This matters because the status code alone is not enough to tell the user
/// what to do. An expired session cookie comes back as **403**, not 401, and is
/// indistinguishable at the HTTP layer from "this account may not read that
/// organisation". Only `error_code` separates them.
struct APIErrorResponse: Decodable {
    struct Detail: Decodable {
        let errorCode: String?
        let errorVisibility: String?

        enum CodingKeys: String, CodingKey {
            case errorCode = "error_code"
            case errorVisibility = "error_visibility"
        }
    }

    struct Payload: Decodable {
        let type: String?
        let message: String?
        let details: Detail?
    }

    let error: Payload?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case error
        case requestId = "request_id"
    }

    var errorCode: String? { error?.details?.errorCode }

    /// The server's own wording, when it is meant for the user to read.
    var userFacingMessage: String? {
        guard let message = error?.message, !message.isEmpty else { return nil }
        return message
    }

    /// Known `error_code` values that mean "the session cookie is no longer
    /// valid", regardless of the status code carrying them.
    static let sessionInvalidCodes: Set<String> = [
        "account_session_invalid",
        "authentication_error",
    ]

    var indicatesInvalidSession: Bool {
        guard let errorCode else { return false }
        return Self.sessionInvalidCodes.contains(errorCode)
    }

    static func decoded(from data: Data) -> APIErrorResponse? {
        try? JSONDecoder().decode(APIErrorResponse.self, from: data)
    }
}
