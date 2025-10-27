import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case noData
}

enum KeychainStore {
    private static func keyAttrs(host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.gighive.credentials",
            kSecAttrAccount as String: host
        ]
    }

    static func save(user: String, pass: String, host: String) throws {
        let valueDict: [String: String] = ["user": user, "pass": pass]
        let data = try JSONSerialization.data(withJSONObject: valueDict, options: [])
        var query = keyAttrs(host: host)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func load(host: String) throws -> (user: String, pass: String)? {
        var query = keyAttrs(host: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: String], let user = dict["user"], let pass = dict["pass"] else {
            throw KeychainError.noData
        }
        return (user, pass)
    }

    static func delete(host: String) throws {
        let status = SecItemDelete(keyAttrs(host: host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
