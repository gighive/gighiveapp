import Foundation

struct GuestStatusResponse: Codable {
    let status: String
    let eventName: String?
    let videoCount: Int?
    let daysRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case eventName = "event_name"
        case videoCount = "video_count"
        case daysRemaining = "days_remaining"
    }
}

struct GuestGalleryVideo: Codable, Identifiable {
    let uploadJobId: Int
    let label: String?
    let streamUrl: String
    let thumbnailUrl: String?
    let displayName: String?
    let approvedAt: String?
    let reportedByMe: Bool

    var id: Int { uploadJobId }

    enum CodingKeys: String, CodingKey {
        case uploadJobId = "upload_job_id"
        case label
        case streamUrl = "stream_url"
        case thumbnailUrl = "thumbnail_url"
        case displayName = "display_name"
        case approvedAt = "approved_at"
        case reportedByMe = "reported_by_me"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uploadJobId = try container.decode(Int.self, forKey: .uploadJobId)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        streamUrl = try container.decode(String.self, forKey: .streamUrl)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        approvedAt = try container.decodeIfPresent(String.self, forKey: .approvedAt)
        reportedByMe = try container.decodeIfPresent(Bool.self, forKey: .reportedByMe) ?? false
    }
}

struct GuestGalleryResponse: Codable {
    let status: String
    let daysRemaining: Int?
    let videoCount: Int?
    let videos: [GuestGalleryVideo]

    enum CodingKeys: String, CodingKey {
        case status
        case daysRemaining = "days_remaining"
        case videoCount = "video_count"
        case videos
    }
}

enum GuestGalleryError: Error, LocalizedError {
    case accessDenied
    case badServer(Int)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Your gallery access could not be verified. The nonce may be invalid."
        case .badServer(let code):
            return "Server returned HTTP \(code)."
        }
    }
}

final class GuestGalleryAPIClient {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func fetchStatus(nonce: String) async throws -> GuestStatusResponse {
        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("guest-status.php")
        guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        comps.queryItems = [URLQueryItem(name: "nonce", value: nonce)]
        guard let url = comps.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 403 { throw GuestGalleryError.accessDenied }
        guard code == 200 else { throw GuestGalleryError.badServer(code) }
        return try JSONDecoder().decode(GuestStatusResponse.self, from: data)
    }

    func fetchGallery(nonce: String) async throws -> GuestGalleryResponse {
        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("guest-gallery.php")
        guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        comps.queryItems = [URLQueryItem(name: "nonce", value: nonce)]
        guard let url = comps.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        logWithTimestamp("[Gallery] fetchGallery HTTP \(code): \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
        if code == 403 { throw GuestGalleryError.accessDenied }
        guard code == 200 else { throw GuestGalleryError.badServer(code) }
        return try JSONDecoder().decode(GuestGalleryResponse.self, from: data)
    }

    private struct ReportResponse: Decodable {
        let reportedByMe: Bool?
        enum CodingKeys: String, CodingKey {
            case reportedByMe = "reported_by_me"
        }
    }

    func setVideoReported(nonce: String, uploadJobId: Int, reported: Bool) async throws -> Bool {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("guest-report.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "nonce": nonce,
            "upload_job_id": uploadJobId,
            "reported": reported
        ] as [String: Any])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 403 { throw GuestGalleryError.accessDenied }
        guard code == 200 else { throw GuestGalleryError.badServer(code) }
        let decoded = try? JSONDecoder().decode(ReportResponse.self, from: data)
        return decoded?.reportedByMe ?? reported
    }

    func deleteVideo(nonce: String, uploadJobId: Int) async throws {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("guest-delete.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "nonce": nonce,
            "upload_job_id": uploadJobId
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 403 { throw GuestGalleryError.accessDenied }
        guard code == 200 else { throw GuestGalleryError.badServer(code) }
    }
}
