import Foundation
import Security

struct UploadedFileTokenEntry: Codable, Identifiable, Equatable {
    let fileId: Int
    let deleteToken: String
    let createdAt: Date
    let eventDate: String
    let orgName: String
    let eventType: String
    let label: String?
    let fileName: String?
    let fileType: String?

    var id: Int { fileId }
}

enum UploaderDeleteTokenStore {
    private static let service = "com.gighive.uploader_delete_tokens"

    private static func keyAttrs(host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
    }

    static func load(host: String) throws -> [UploadedFileTokenEntry] {
        var query = keyAttrs(host: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }

        return try JSONDecoder().decode([UploadedFileTokenEntry].self, from: data)
    }

    static func save(host: String, entries: [UploadedFileTokenEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        var query = keyAttrs(host: host)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func upsert(host: String, entry: UploadedFileTokenEntry) throws {
        var entries = try load(host: host)
        if let idx = entries.firstIndex(where: { $0.fileId == entry.fileId }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        entries.sort { $0.createdAt > $1.createdAt }
        try save(host: host, entries: entries)
    }

    static func remove(host: String, fileId: Int) throws {
        let entries = try load(host: host).filter { $0.fileId != fileId }
        try save(host: host, entries: entries)
    }

    static func clear(host: String) throws {
        let status = SecItemDelete(keyAttrs(host: host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
