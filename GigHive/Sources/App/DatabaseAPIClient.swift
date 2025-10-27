import Foundation

enum DatabaseError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid database URL"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code):
            if code == 401 { return "HTTP Error 401 – incorrect username or password" }
            return "HTTP Error \(code)"
        }
    }
}

final class DatabaseAPIClient {
    let baseURL: URL
    let basicAuth: (user: String, pass: String)?
    let allowInsecure: Bool

    init(baseURL: URL, basicAuth: (String, String)?, allowInsecure: Bool = false) {
        self.baseURL = baseURL
        self.basicAuth = basicAuth
        self.allowInsecure = allowInsecure
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

        let cfg = URLSessionConfiguration.ephemeral
        let session: URLSession
        if allowInsecure {
            session = URLSession(configuration: cfg, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
        } else {
            session = URLSession(configuration: cfg)
        }

        // Debug logging
        logWithTimestamp("[DBClient] GET \(url.absoluteString); authUser=\(basicAuth?.user ?? "<none>"); insecureTLS=\(allowInsecure)")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DatabaseError.invalidResponse }
        logWithTimestamp("[DBClient] HTTP \(http.statusCode) for \(url.path)?\(components?.percentEncodedQuery ?? "")")
        guard http.statusCode == 200 else { throw DatabaseError.httpError(http.statusCode) }
        let decoded = try JSONDecoder().decode(MediaListResponse.self, from: data)
        return decoded.entries
    }
}
