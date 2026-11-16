import Foundation
import LocalAuthentication
import Security

/// Stores passwords and codes from the clipboard — one Keychain item each:
/// - data protection keychain, so the flags below actually apply;
/// - never synced to iCloud;
/// - only on this Mac, only while it's unlocked;
/// - reading requires Touch ID or the user's password.
enum SecretVault {
    private static let service = "com.azam.CmdPlus.clipboard-secret"

    struct VaultError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? ""
            return "\(message) (OSStatus \(status))"
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func store(_ secret: String, account: String) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            throw VaultError(status: errSecParam)
        }

        var query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(secret.utf8)
        query[kSecAttrAccessControl as String] = access
        query[kSecAttrLabel as String] = "CmdPlus — Clipboard"

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError(status: status) }
    }

    static func reveal(account: String, reason: String) async throws -> String {
        let context = LAContext()
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)

        // Reuse the already-authenticated context so the user isn't asked twice.
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8)
        else {
            throw VaultError(status: status == errSecSuccess ? errSecDecode : status)
        }
        return secret
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
