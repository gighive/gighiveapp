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
        // Create NetworkProgressUploadClient directly for real network progress tracking
        let networkClient = NetworkProgressUploadClient(
            baseURL: baseURL,
            basicAuth: basicAuth,
            allowInsecure: allowInsecure
        )
        self.currentNetworkClient = networkClient  // Store reference for cancellation
        
        return try await withTaskCancellationHandler {
            try await networkClient.uploadFile(
                payload: payload,
                progressHandler: { completed, total in
                    progress?(completed, total)
                }
            )
        } onCancel: {
            // When Swift Task is cancelled, cancel the underlying network upload
            logWithTimestamp("⚠️ [uploadWithMultipartInputStream] Task cancelled - cancelling network upload")
            networkClient.cancelUpload()
        }
    }

    
    /// Cancel the current upload
    func cancelCurrentUpload() {
        logWithTimestamp("🔴 [UploadClient] cancelCurrentUpload() called")
        currentNetworkClient?.cancelUpload()
        // DON'T clear currentNetworkClient here - it needs to stay alive to fire the completion callback
        // which will resume the continuation. It will be cleared when the completion fires.
        logWithTimestamp("🔴 [UploadClient] cancelCurrentUpload() completed - currentNetworkClient still alive for callback")
    }
}
