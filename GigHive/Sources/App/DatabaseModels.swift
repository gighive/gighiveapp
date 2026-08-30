import Foundation

struct MediaEntry: Codable, Identifiable {
    let id: Int
    let index: Int
    let date: String
    let orgName: String
    let duration: String
    let durationSeconds: Int
    let songTitle: String
    let fileType: String
    let fileName: String
    let url: String
    let thumbnailUrl: String?
    /// Server-authoritative delete eligibility flag (Phase 5 refactor).
    /// Decoded with a false default so responses from pre-Phase-2 servers
    /// (which omit the field) do not cause a decode error.
    let canDelete: Bool

    enum CodingKeys: String, CodingKey {
        case id, index, date, duration
        case orgName = "org_name"
        case durationSeconds = "duration_seconds"
        case songTitle = "song_title"
        case fileType = "file_type"
        case fileName = "file_name"
        case url
        case thumbnailUrl = "thumbnail_url"
        case canDelete = "can_delete"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(Int.self, forKey: .id)
        index           = try c.decode(Int.self, forKey: .index)
        date            = try c.decode(String.self, forKey: .date)
        orgName         = try c.decode(String.self, forKey: .orgName)
        duration        = try c.decode(String.self, forKey: .duration)
        durationSeconds = try c.decode(Int.self, forKey: .durationSeconds)
        songTitle       = try c.decode(String.self, forKey: .songTitle)
        fileType        = try c.decode(String.self, forKey: .fileType)
        fileName        = try c.decode(String.self, forKey: .fileName)
        url             = try c.decode(String.self, forKey: .url)
        thumbnailUrl    = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        canDelete       = try c.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
    }
}

struct MediaListResponse: Codable {
    let entries: [MediaEntry]
}
