import Foundation

struct GuestUploadRecord: Codable {
    let statusNonce: String
    let uploadJobId: Int        // upload_jobs.id (INT auto-increment)
    let eventName: String       // e.g. "StormPigs — 2026-07-17"
    let submittedAt: Date
    var approvalStatus: String  // "pending" | "approved" | "rejected" | "expired"
    var lastSeenVideoCount: Int
    var daysRemaining: Int?     // nil = indefinite
}

extension GuestUploadRecord {
    // SonarQube RSPEC-5334: UserDefaults is intentional here — the status_nonce is device-bound
    // by design (accountless model with no recovery path). Keychain portability is unnecessary
    // and contrary to the feature's explicit "device-bound access" guarantee. Hotspot reviewed
    // and accepted.
    private static let defaultsKey = "guestUploadHistory"

    static func load() -> [GuestUploadRecord] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let records = try? JSONDecoder().decode([GuestUploadRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func save(_ records: [GuestUploadRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    /// Insert or replace the record matching on `statusNonce`.
    static func upsert(_ record: GuestUploadRecord) {
        var records = load()
        if let idx = records.firstIndex(where: { $0.statusNonce == record.statusNonce }) {
            records[idx] = record
        } else {
            records.append(record)
        }
        save(records)
    }
}
