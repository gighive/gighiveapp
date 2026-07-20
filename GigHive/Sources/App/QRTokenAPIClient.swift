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
            logWithTimestamp("[QRTokenAPI] BAIL: malformedBaseURL from \(url)")
            throw QRTokenError.malformedBaseURL
        }
        comps.queryItems = [URLQueryItem(name: "token", value: rawToken)]
        guard let requestURL = comps.url else {
            logWithTimestamp("[QRTokenAPI] BAIL: could not build requestURL from comps")
            throw QRTokenError.malformedBaseURL
        }
        logWithTimestamp("[QRTokenAPI] requesting: \(requestURL.absoluteString)")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logWithTimestamp("[QRTokenAPI] URLSession error: \(type(of: error)) code=\((error as NSError).code) domain=\((error as NSError).domain) desc=\(error.localizedDescription)")
            throw QRTokenError.networkError(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        logWithTimestamp("[QRTokenAPI] response status=\(status) body=\(rawBody.prefix(300))")
        guard status == 200 else {
            logWithTimestamp("[QRTokenAPI] non-200 status=\(status) — throwing invalidOrExpired")
            throw QRTokenError.invalidOrExpired(status)
        }
        do {
            let decoded = try JSONDecoder().decode(QREventDetails.self, from: data)
            logWithTimestamp("[QRTokenAPI] decode success: org=\(decoded.orgName) date=\(decoded.eventDate)")
            return decoded
        } catch {
            logWithTimestamp("[QRTokenAPI] JSON decode error: \(error)")
            throw error
        }
    }
}
