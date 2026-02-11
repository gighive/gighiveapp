import Foundation
import UniformTypeIdentifiers

struct UploadPayload {
    var fileURL: URL
    var eventDate: Date
    var orgName: String
    var eventType: String
    var label: String?
    var participants: String?
    var keywords: String?
    var location: String?
    var rating: String?
    var notes: String?
}

// Insecure trust delegate — accepts any TLS certificate. Use ONLY when user opts in.
final class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    static let shared = InsecureTrustDelegate()
    private override init() { super.init() }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

final class UploadClient {
    let baseURL: URL
    let session: URLSession
    let basicAuth: (user: String, pass: String)?
    let allowInsecure: Bool
    private var currentNetworkClient: NetworkProgressUploadClient?
    private var currentTusClient: TUSUploadClient?

    init(baseURL: URL, basicAuth: (String,String)? = nil, useBackgroundSession: Bool = false, allowInsecure: Bool = false) {
        self.baseURL = baseURL
        self.basicAuth = basicAuth
        self.allowInsecure = allowInsecure
        if useBackgroundSession {
            // Note: background sessions are not supported in app extensions.
            // Use only in the main app when long-running transfers are desired.
            let cfg = URLSessionConfiguration.background(withIdentifier: "com.yourcompany.gighive.uploads")
            cfg.waitsForConnectivity = true
            cfg.allowsExpensiveNetworkAccess = true
            cfg.allowsConstrainedNetworkAccess = true
            if allowInsecure {
                self.session = URLSession(configuration: cfg, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
            } else {
                self.session = URLSession(configuration: cfg)
            }
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.waitsForConnectivity = true
            cfg.allowsExpensiveNetworkAccess = true
            cfg.allowsConstrainedNetworkAccess = true
            cfg.timeoutIntervalForRequest = 120
            cfg.timeoutIntervalForResource = 600
            if allowInsecure {
                self.session = URLSession(configuration: cfg, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
            } else {
                self.session = URLSession(configuration: cfg)
            }
        }
    }
    
    /// Upload with MultipartInputStream streaming for all files
    /// Uses memory-efficient streaming approach with custom InputStream for better cancellation and consistent UX
    func uploadWithMultipartInputStream(_ payload: UploadPayload, progress: ((Int64, Int64) -> Void)? = nil) async throws -> (status: Int, data: Data, requestURL: URL) {
        guard let label = payload.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            throw NSError(domain: "UploadClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Label is required"])
        }

        let tusBaseURL = baseURL.appendingPathComponent("files/")
        logWithTimestamp("🚀 [UploadClient] Starting TUS upload")
        logWithTimestamp("🌐 [UploadClient] tusBaseURL=\(tusBaseURL.absoluteString)")
        let tusClient = try TUSUploadClient(
            tusBaseURL: tusBaseURL,
            basicAuth: basicAuth.map { (user: $0.user, pass: $0.pass) },
            allowInsecure: allowInsecure
        )
        self.currentTusClient = tusClient

        return try await withTaskCancellationHandler {
            let uploadURL = try await tusClient.uploadFile(payload: payload, progress: progress)
            logWithTimestamp("✅ [UploadClient] TUS upload finished, uploadURL=\(uploadURL.absoluteString)")
            let uploadID = uploadURL.lastPathComponent
            logWithTimestamp("🔎 [UploadClient] Extracted upload_id=\(uploadID)")
            let mergedPayload = UploadPayload(
                fileURL: payload.fileURL,
                eventDate: payload.eventDate,
                orgName: payload.orgName,
                eventType: payload.eventType,
                label: label,
                participants: payload.participants,
                keywords: payload.keywords,
                location: payload.location,
                rating: payload.rating,
                notes: payload.notes
            )
            logWithTimestamp("📦 [UploadClient] Finalizing TUS upload")
            let result = try await finalizeTusUpload(uploadID: uploadID, payload: mergedPayload)
            logWithTimestamp("🏁 [UploadClient] Finalize finished [\(result.status)]")
            return result
        } onCancel: {
            logWithTimestamp("⚠️ [uploadWithMultipartInputStream] Task cancelled - cancelling TUS upload")
            tusClient.cancel()
        }
    }

    private func finalizeTusUpload(uploadID: String, payload: UploadPayload) async throws -> (status: Int, data: Data, requestURL: URL) {
        let finalizeURL = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("uploads")
            .appendingPathComponent("finalize")

        logWithTimestamp("🌐 [UploadClient] finalizeURL=\(finalizeURL.absoluteString)")

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var body: [String: Any] = [
            "upload_id": uploadID,
            "event_date": df.string(from: payload.eventDate),
            "org_name": payload.orgName,
            "event_type": payload.eventType,
            "label": payload.label ?? ""
        ]
        if let participants = payload.participants { body["participants"] = participants }
        if let keywords = payload.keywords { body["keywords"] = keywords }
        if let location = payload.location { body["location"] = location }
        if let rating = payload.rating { body["rating"] = rating }
        if let notes = payload.notes { body["notes"] = notes }

        let json = try JSONSerialization.data(withJSONObject: body, options: [])

        var request = URLRequest(url: finalizeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json,text/html;q=0.9", forHTTPHeaderField: "Accept")

        if let auth = basicAuth {
            let credentials = "\(auth.user):\(auth.pass)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, from: json) { data, response, error in
                if let error {
                    logWithTimestamp("❌ [UploadClient] Finalize error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logWithTimestamp("📥 [UploadClient] Finalize response [\(status)] bytes=\(data?.count ?? 0)")
                continuation.resume(returning: (status: status, data: data ?? Data(), requestURL: finalizeURL))
            }
            task.resume()
        }
    }

    
    /// Cancel the current upload
    func cancelCurrentUpload() {
        logWithTimestamp("🔴 [UploadClient] cancelCurrentUpload() called")
        currentTusClient?.cancel()
        currentNetworkClient?.cancelUpload()
        // DON'T clear currentNetworkClient here - it needs to stay alive to fire the completion callback
        // which will resume the continuation. It will be cleared when the completion fires.
        logWithTimestamp("🔴 [UploadClient] cancelCurrentUpload() completed - currentNetworkClient still alive for callback")
    }
}
