import Foundation
import Security

public protocol TokenStore: AnyObject, Sendable {
    func readRefreshToken() -> String?
    func writeRefreshToken(_ token: String)
    func deleteRefreshToken()
}

public final class KeychainStore: TokenStore, @unchecked Sendable {
    private let service = "com.floatinglyric.tokens"
    private let account = "refresh-token"

    public init() {}

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func readRefreshToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func writeRefreshToken(_ token: String) {
        deleteRefreshToken()
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    public func deleteRefreshToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var token: String?
    public init(token: String? = nil) { self.token = token }
    public func readRefreshToken() -> String? { token }
    public func writeRefreshToken(_ token: String) { self.token = token }
    public func deleteRefreshToken() { token = nil }
}
