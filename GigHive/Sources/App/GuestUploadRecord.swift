import Foundation

struct GuestUploadRecord: Codable {
    let statusNonce: String
    let uploadJobId: Int        // upload_jobs.id (INT auto-increment)
    let eventName: String       // e.g. "StormPigs — 2026-07-17"
    let submittedAt: Date
    let baseURLString: String   // server origin for status/gallery polling
    var approvalStatus: String  // "pending" | "approved" | "rejected" | "expired"
    var lastSeenVideoCount: Int
    var viewedUploadJobIds: [Int]  // job IDs the user has tapped Play on; badge clears per-video
    var daysRemaining: Int?     // nil = indefinite

    // Custom decoder so records persisted before viewedUploadJobIds was added decode successfully.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusNonce        = try c.decode(String.self,  forKey: .statusNonce)
        uploadJobId        = try c.decode(Int.self,     forKey: .uploadJobId)
        eventName          = try c.decode(String.self,  forKey: .eventName)
        submittedAt        = try c.decode(Date.self,    forKey: .submittedAt)
        baseURLString      = try c.decode(String.self,  forKey: .baseURLString)
        approvalStatus     = try c.decode(String.self,  forKey: .approvalStatus)
        lastSeenVideoCount = try c.decode(Int.self,     forKey: .lastSeenVideoCount)
        viewedUploadJobIds = (try? c.decode([Int].self, forKey: .viewedUploadJobIds)) ?? []
        daysRemaining      = try? c.decode(Int.self,    forKey: .daysRemaining)
    }

    init(statusNonce: String, uploadJobId: Int, eventName: String, submittedAt: Date,
         baseURLString: String, approvalStatus: String, lastSeenVideoCount: Int,
         viewedUploadJobIds: [Int] = [], daysRemaining: Int?) {
        self.statusNonce        = statusNonce
        self.uploadJobId        = uploadJobId
        self.eventName          = eventName
        self.submittedAt        = submittedAt
        self.baseURLString      = baseURLString
        self.approvalStatus     = approvalStatus
        self.lastSeenVideoCount = lastSeenVideoCount
        self.viewedUploadJobIds = viewedUploadJobIds
        self.daysRemaining      = daysRemaining
    }
}

extension GuestUploadRecord {
    // SonarQube RSPEC-5334: UserDefaults is intentional here — the status_nonce is device-bound
    // by design (accountless model with no recovery path). Keychain portability is unnecessary
    // and contrary to the feature's explicit "device-bound access" guarantee. Hotspot reviewed
    // and accepted.
    private static let defaultsKey = "guestUploadHistory"
    private static let dismissedBannersKey = "dismissedApprovalBanners"

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

    static func loadDismissedBanners() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedBannersKey) ?? [])
    }

    static func dismissBanner(nonce: String) {
        var arr = UserDefaults.standard.stringArray(forKey: dismissedBannersKey) ?? []
        if !arr.contains(nonce) { arr.append(nonce) }
        UserDefaults.standard.set(arr, forKey: dismissedBannersKey)
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
