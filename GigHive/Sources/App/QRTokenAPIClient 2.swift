import Foundation

enum QRTokenError: Error, LocalizedError {
    case invalidOrExpired(Int)
    case malformedBaseURL
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidOrExpired:
            return "This upload link is invalid or has expired."
        case .malformedBaseURL:
            return "Could not construct the validation URL."
        case .networkError(let e):
            return e.localizedDescription
        }
    }
}

final class QRTokenAPIClient {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func validateToken(_ rawToken: String) async throws -> QREventDetails {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("upload-token.php")
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw QRTokenError.malformedBaseURL
        }
        comps.queryItems = [URLQueryItem(name: "token", value: rawToken)]
        guard let requestURL = comps.url else {
            throw QRTokenError.malformedBaseURL
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw QRTokenError.invalidOrExpired(status)
        }
        return try JSONDecoder().decode(QREventDetails.self, from: data)
    }
}
