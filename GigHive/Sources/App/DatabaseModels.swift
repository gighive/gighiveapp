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

    enum CodingKeys: String, CodingKey {
        case id, index, date, duration
        case orgName = "org_name"
        case durationSeconds = "duration_seconds"
        case songTitle = "song_title"
        case fileType = "file_type"
        case fileName = "file_name"
        case url
    }
}

struct MediaListResponse: Codable {
    let entries: [MediaEntry]
}
