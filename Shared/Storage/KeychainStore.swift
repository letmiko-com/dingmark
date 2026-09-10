import Foundation
import Security

/// The linkding API token: Keychain only, shared with the extensions through
/// the App Group used as keychain access group. Never UserDefaults, never logs.
enum KeychainStore {
    private static let service = "app.letmiko.dingmark"
    private static let account = "linkding-api-token"

    static func readToken() -> String? {
        for group in candidateGroups {
            var query = baseQuery(accessGroup: group)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data,
               let token = String(data: data, encoding: .utf8), !token.isEmpty {
                return token
            }
        }
        return nil
    }

    @discardableResult
    static func writeToken(_ token: String) -> Bool {
        deleteToken()
        for group in candidateGroups {
            var add = baseQuery(accessGroup: group)
            add[kSecValueData as String] = Data(token.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(add as CFDictionary, nil)
            if status == errSecSuccess { return true }
            // -34018 errSecMissingEntitlement: the access group is not
            // available (unit tests, simulator without the entitlement).
            // Fall through to the plain keychain.
        }
        return false
    }

    static func deleteToken() {
        for group in candidateGroups {
            SecItemDelete(baseQuery(accessGroup: group) as CFDictionary)
        }
    }

    private static var candidateGroups: [String?] { [AppGroup.identifier, nil] }

    private static func baseQuery(accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

/// Injectable boundary for session tests; production credentials still go
/// exclusively through KeychainStore.
protocol TokenStorage {
    func readToken() -> String?
    func writeToken(_ token: String) -> Bool
    func deleteToken()
}

struct KeychainTokenStorage: TokenStorage {
    func readToken() -> String? { KeychainStore.readToken() }
    func writeToken(_ token: String) -> Bool { KeychainStore.writeToken(token) }
    func deleteToken() { KeychainStore.deleteToken() }
}
