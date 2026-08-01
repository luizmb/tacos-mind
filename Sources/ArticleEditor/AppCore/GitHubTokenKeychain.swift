import AppDomain
import Foundation
import Security

/// Stores the GitHub Personal Access Token — and only the token; `repoURL`/`branch`
/// aren't secret and live in a plain settings file instead (see `World+Live.swift`).
/// The first Keychain wrapper in this user's Swift apps (none of PookiePayslip/
/// NetworkTools/ios.lu had one) — a direct `Security`-framework wrapper, since nothing
/// like KeychainAccess is already vendored anywhere.
enum GitHubTokenKeychain {
    private static let service = "io.lu.ArticleEditor.github-token"
    private static let account = "github-pat"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) -> Result<Void, GitHubError> {
        guard let data = token.data(using: .utf8) else {
            return .failure(.network("token isn't valid UTF-8"))
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                return .failure(.network("Keychain add failed (status \(addStatus))"))
            }
            return .success(())
        }
        guard updateStatus == errSecSuccess else {
            return .failure(.network("Keychain update failed (status \(updateStatus))"))
        }
        return .success(())
    }

    /// Unlinking a repo removes the token entirely rather than leaving a stale one
    /// behind — `errSecItemNotFound` isn't an error here, there's just nothing to remove.
    static func delete() -> Result<Void, GitHubError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .failure(.network("Keychain delete failed (status \(status))"))
        }
        return .success(())
    }
}
