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
    let basicAuth: (user: String, pass: String)?
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

    init(baseURL: URL, basicAuth: (String, String)?, allowInsecure: Bool = false) {
        self.baseURL = baseURL
        self.basicAuth = basicAuth
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
        if let auth = basicAuth {
            let credentials = "\(auth.user):\(auth.pass)"
            let base64 = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }

        let session = makeSession()

        // Debug logging
        logWithTimestamp("[DBClient] GET \(url.absoluteString); authUser=\(basicAuth?.user ?? "<none>"); insecureTLS=\(allowInsecure)")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DatabaseError.invalidResponse }
        logWithTimestamp("[DBClient] HTTP \(http.statusCode) for \(url.path)?\(components?.percentEncodedQuery ?? "")")
        guard http.statusCode == 200 else { throw DatabaseError.httpError(http.statusCode) }
        let decoded = try JSONDecoder().decode(MediaListResponse.self, from: data)
        return decoded.entries
    }

    func deleteMediaFile(fileId: Int, deleteToken: String) async throws -> DeleteMediaResponse {
        guard fileId > 0 else { throw DatabaseError.serverMessage("Invalid file_id") }
        let token = deleteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw DatabaseError.serverMessage("Missing delete_token") }

        let url = baseURL.appendingPathComponent("db/delete_media_files.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json,text/html;q=0.9", forHTTPHeaderField: "Accept")

        if let auth = basicAuth {
            let credentials = "\(auth.user):\(auth.pass)"
            let base64 = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "file_id": fileId,
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
