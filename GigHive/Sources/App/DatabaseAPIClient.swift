import Foundation

enum DatabaseError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid database URL"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code):
            if code == 401 { return "HTTP Error 401 – incorrect username or password" }
            return "HTTP Error \(code)"
        case .serverMessage(let msg):
            return msg
        }
    }
}

final class DatabaseAPIClient {
    let baseURL: URL
    let credential: AuthCredential?
    let allowInsecure: Bool

    struct DeleteMediaResponse: Codable {
        let success: Bool
        let deletedCount: Int
        let errorCount: Int

        enum CodingKeys: String, CodingKey {
            case success
            case deletedCount = "deleted_count"
            case errorCount = "error_count"
        }
    }

    init(baseURL: URL, credential: AuthCredential?, allowInsecure: Bool = false) {
        self.baseURL = baseURL
        self.credential = credential
        self.allowInsecure = allowInsecure
    }

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        let session: URLSession
        if allowInsecure {
            session = URLSession(configuration: cfg, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
        } else {
            session = URLSession(configuration: cfg)
        }
        return session
    }

    func fetchMediaList() async throws -> [MediaEntry] {
        var components = URLComponents(url: baseURL.appendingPathComponent("db/database.php"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "format", value: "json")]
        guard let url = components?.url else { throw DatabaseError.invalidURL }

        var request = URLRequest(url: url)
        credential?.apply(to: &request)

        let session = makeSession()

        // Debug logging
        logWithTimestamp("[DBClient] GET \(url.absoluteString); authUser=\(credential?.displayUser ?? "<none>"); insecureTLS=\(allowInsecure)")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DatabaseError.invalidResponse }
        logWithTimestamp("[DBClient] HTTP \(http.statusCode) for \(url.path)?\(components?.percentEncodedQuery ?? "")")
        guard http.statusCode == 200 else { throw DatabaseError.httpError(http.statusCode) }
        let decoded = try JSONDecoder().decode(MediaListResponse.self, from: data)
        return decoded.entries
    }

    /// Admin delete — sends `{"asset_ids": [fileId]}`. No delete token required; the server
    /// trusts the admin HTTP credential and skips token validation entirely.
    func deleteMediaFileAsAdmin(fileId: Int) async throws -> DeleteMediaResponse {
        guard fileId > 0 else { throw DatabaseError.serverMessage("Invalid file_id") }

        let url = baseURL.appendingPathComponent("db/delete_media_files.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json,text/html;q=0.9", forHTTPHeaderField: "Accept")
        credential?.apply(to: &request)

        let body: [String: Any] = ["asset_ids": [fileId]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let session = makeSession()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DatabaseError.invalidResponse }

        if http.statusCode != 200 {
            if let msg = String(data: data, encoding: .utf8), !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw DatabaseError.serverMessage(msg)
            }
            throw DatabaseError.httpError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(DeleteMediaResponse.self, from: data)
        } catch {
            throw DatabaseError.invalidResponse
        }
    }

    /// Uploader delete — sends `{"asset_id": fileId, "delete_token": token}`. The server
    /// validates the token hash against the stored value before deleting.
    func deleteMediaFile(fileId: Int, deleteToken: String) async throws -> DeleteMediaResponse {
        guard fileId > 0 else { throw DatabaseError.serverMessage("Invalid file_id") }
        let token = deleteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw DatabaseError.serverMessage("Missing delete_token") }

        let url = baseURL.appendingPathComponent("db/delete_media_files.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json,text/html;q=0.9", forHTTPHeaderField: "Accept")

        credential?.apply(to: &request)

        let body: [String: Any] = [
            "asset_id": fileId,
            "delete_token": token
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let session = makeSession()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DatabaseError.invalidResponse }

        if http.statusCode != 200 {
            if http.statusCode == 403 {
                throw DatabaseError.httpError(403)
            }
            if let msg = String(data: data, encoding: .utf8), !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw DatabaseError.serverMessage(msg)
            }
            throw DatabaseError.httpError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(DeleteMediaResponse.self, from: data)
        } catch {
            throw DatabaseError.invalidResponse
        }
    }
}
