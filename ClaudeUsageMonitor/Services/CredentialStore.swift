import Foundation
import Security
import os

/// A secret held in the Keychain rather than in UserDefaults.
///
/// Both of these are cookies scoped to claude.ai. The session key in particular
/// grants full access to the account, so it is treated like a password: it never
/// touches UserDefaults, is never logged, and is not synchronised to iCloud.
enum CredentialKey: String, CaseIterable {
    /// claude.ai session cookie (`sk-ant-sid01-…`).
    case sessionKey

    /// Cloudflare clearance cookie, needed when claude.ai is actively
    /// challenging requests. Optional — many requests succeed without it.
    case cfClearance
}

/// Reads and writes credentials in the Keychain, and scrubs any legacy
/// plaintext copies left behind in UserDefaults by earlier versions.
///
/// Items are stored in the file-based Keychain. The data-protection Keychain
/// (`kSecUseDataProtectionKeychain`) would be the more modern choice, but on
/// macOS it requires a `keychain-access-groups` entitlement that this app does
/// not carry; without it every write fails with `errSecMissingEntitlement`
/// (-34018). A sandboxed, signed app can use the file-based Keychain for its
/// own items with no additional entitlement, and the sandbox still confines
/// those items to this application.
final class CredentialStore {
    private let service: String
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "woeichwan.ClaudeUsageMonitor", category: "CredentialStore")

    init(
        service: String = Bundle.main.bundleIdentifier ?? "woeichwan.ClaudeUsageMonitor",
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
    }

    // MARK: - Reading and writing

    /// The stored value, or an empty string if absent or unreadable.
    func value(for key: CredentialKey) -> String {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                logger.error("Keychain item for \(key.rawValue, privacy: .public) was not valid UTF-8")
                return ""
            }
            return string
        case errSecItemNotFound:
            return ""
        default:
            logger.error("Keychain read for \(key.rawValue, privacy: .public) failed: OSStatus \(status)")
            return ""
        }
    }

    /// Stores a value, or removes the item entirely when the value is blank.
    ///
    /// Whitespace and newlines are trimmed here so that a credential pasted
    /// from a browser's developer tools — which frequently carries a trailing
    /// newline — is stored in the form the API expects.
    ///
    /// Returns `false` if the value could not be stored. Callers that are about
    /// to discard the only other copy of a credential **must** check this.
    @discardableResult
    func setValue(_ value: String, for key: CredentialKey) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            removeValue(for: key)
            return true
        }

        let data = Data(trimmed.utf8)
        let query = baseQuery(for: key)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var insertion = query
            insertion[kSecValueData as String] = data
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Keychain insert for \(key.rawValue, privacy: .public) failed: OSStatus \(addStatus)")
                return false
            }
            return true
        default:
            logger.error("Keychain update for \(key.rawValue, privacy: .public) failed: OSStatus \(updateStatus)")
            return false
        }
    }

    func removeValue(for key: CredentialKey) {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete for \(key.rawValue, privacy: .public) failed: OSStatus \(status)")
        }
    }

    // MARK: - Legacy migration

    /// Moves any plaintext credential written by versions that used
    /// `@AppStorage` into the Keychain, then deletes the UserDefaults entry.
    ///
    /// The plaintext copy is only removed once the Keychain value has been
    /// written *and read back intact*. If the Keychain is unavailable the
    /// plaintext copy is deliberately left in place: a credential still sitting
    /// in UserDefaults is a problem, but destroying the user's only copy of it
    /// is a worse one. Safe to call on every launch; once the defaults entry is
    /// gone this does nothing.
    func migrateLegacyPlaintextCredentials() {
        let legacyDefaultsKey = CredentialKey.sessionKey.rawValue

        guard let legacy = defaults.string(forKey: legacyDefaultsKey) else { return }
        let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing of value to lose — just clear the entry.
        guard !trimmed.isEmpty else {
            defaults.removeObject(forKey: legacyDefaultsKey)
            return
        }

        // The Keychain already holds a value; treat it as authoritative and
        // drop the stale plaintext copy.
        guard value(for: .sessionKey).isEmpty else {
            defaults.removeObject(forKey: legacyDefaultsKey)
            logger.notice("Keychain already held a session key; removed the stale plaintext copy")
            return
        }

        // Write, then prove the write survived before discarding the original.
        guard setValue(trimmed, for: .sessionKey), value(for: .sessionKey) == trimmed else {
            logger.error("""
                Keychain write failed during migration. Keeping the plaintext copy in \
                UserDefaults so the credential is not lost — it will be retried on the \
                next launch.
                """)
            return
        }

        defaults.removeObject(forKey: legacyDefaultsKey)
        logger.notice("Migrated session key into the Keychain and removed the plaintext copy")
    }

    // MARK: - Private

    private func baseQuery(for key: CredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
