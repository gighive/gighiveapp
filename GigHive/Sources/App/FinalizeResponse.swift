import Foundation

struct FinalizeResponse: Codable {
    let id: Int
    let fileName: String?
    let fileType: String?
    let mimeType: String?
    let sizeBytes: Int?
    let checksumSha256: String?
    let eventDate: String?
    let orgName: String?
    let eventType: String?
    let label: String?
    let deleteToken: String?
    let statusNonce: String?
    let uploadJobId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case fileName = "file_name"
        case fileType = "file_type"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case checksumSha256 = "checksum_sha256"
        case eventDate = "event_date"
        case orgName = "org_name"
        case eventType = "event_type"
        case label
        case deleteToken = "delete_token"
        case statusNonce = "status_nonce"
        case uploadJobId = "upload_job_id"
    }
}
