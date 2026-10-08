import Foundation
import Security
import LocalAuthentication

enum KeychainStore {
    enum Failure: Error { case unavailable }
    static func save(_ value: String, name: String) throws {
        guard name != "viewing-key" else { throw Failure.unavailable }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.zec.buyingprice", kSecAttrAccount as String: name]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.unavailable }
        } else if status != errSecSuccess { throw Failure.unavailable }
    }
    static func read(name: String) throws -> String? {
        guard name != "viewing-key" else { throw Failure.unavailable }
        return try read(name: name, context: nil)
    }
    static func contains(name: String) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.zec.buyingprice", kSecAttrAccount as String: name,
            kSecUseAuthenticationContext as String: context, kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var attributes: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &attributes) != errSecItemNotFound
    }
    @MainActor static func readLegacyViewingKey(context: LAContext,
        authorized: @escaping @MainActor () -> Bool = { true }) async throws -> String? {
        guard authorized() else { throw Failure.unavailable }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication,
            localizedReason: "Authorize migration of the saved viewing-only wallet.") else { throw Failure.unavailable }
        guard authorized(), !Task.isCancelled else { throw Failure.unavailable }
        return try read(name: "viewing-key", context: context)
    }
    static func removeLegacyViewingKey() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.zec.buyingprice", kSecAttrAccount as String: "viewing-key"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.unavailable }
    }
    private static func read(name: String, context: LAContext?) throws -> String? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.zec.buyingprice", kSecAttrAccount as String: name,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.unavailable }
        return String(data: data, encoding: .utf8)
    }
}
