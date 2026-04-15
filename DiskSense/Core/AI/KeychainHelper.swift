import Foundation
import Security

enum KeychainError: Error {
    case notFound
    case unexpectedStatus(OSStatus)
}

enum KeychainHelper {
    private static let service = "com.yourname.DiskSense"

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.unexpectedStatus(-1) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func retrieve(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { throw KeychainError.notFound }
        guard status == errSecSuccess,
              let data = out as? Data,
              let str = String(data: data, encoding: .utf8)
        else { throw KeychainError.unexpectedStatus(status) }
        return str
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func has(key: String) -> Bool {
        (try? retrieve(key: key)) != nil
    }
}
