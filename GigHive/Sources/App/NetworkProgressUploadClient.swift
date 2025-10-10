import Foundation
import UniformTypeIdentifiers

/// Network-aware upload client that tracks REAL network progress
/// Uses direct streaming: builds multipart body on-the-fly and streams directly to network
final class NetworkProgressUploadClient: NSObject {
    private let baseURL: URL
    private let basicAuth: (user: String, pass: String)?
    private let allowInsecure: Bool
    private var session: URLSession!
    
    // Progress tracking
    private var progressHandler: ((Int64, Int64) -> Void)?
    private var completion: ((Result<(status: Int, data: Data, requestURL: URL), Error>) -> Void)?
    private var currentUploadTask: URLSessionUploadTask?
    private var responseData = Data()  // Accumulate response data
    private var currentInputStream: MultipartInputStream?  // Store stream for delegate
    
    init(baseURL: URL, basicAuth: (String, String)?, allowInsecure: Bool) {
        self.baseURL = baseURL
        self.basicAuth = basicAuth
        self.allowInsecure = allowInsecure
        
        super.init()
        
        // Configure session with longer timeouts for large file uploads
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300  // 5 minutes per request
        config.timeoutIntervalForResource = 3600  // 1 hour total for the upload
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        
        if allowInsecure {
            let delegate = InsecureTrustUploadDelegate(uploadClient: self)
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }
    }
    
    /// Upload file with REAL network progress tracking using direct streaming
    /// Streams multipart body directly from file without creating temp files
    func uploadFile(
        payload: UploadPayload,
        progressHandler: @escaping (Int64, Int64) -> Void,
        completion: @escaping (Result<(status: Int, data: Data, requestURL: URL), Error>) -> Void
    ) {
        self.progressHandler = progressHandler
        self.completion = completion
        self.responseData = Data()  // Reset response data accumulator
        
        Task {
            do {
                print("🚀 Direct streaming upload starting for: \(payload.fileURL.lastPathComponent)")
                
                // Build URL
                let apiURL = baseURL
                    .appendingPathComponent("api")
                    .appendingPathComponent("uploads.php")
                var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
                components?.queryItems = [URLQueryItem(name: "ui", value: "json")]
                guard let finalURL = components?.url else { 
                    completion(.failure(URLError(.badURL)))
                    return
                }
                
                var request = URLRequest(url: finalURL)
                request.httpMethod = "POST"
                
                // Add basic auth
                if let auth = basicAuth {
                    let credentials = "\(auth.user):\(auth.pass)"
                    let encodedCredentials = Data(credentials.utf8).base64EncodedString()
                    request.setValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")
                }
                
                request.setValue("application/json,text/html;q=0.9", forHTTPHeaderField: "Accept")
                
                // Create multipart stream
                let boundary = "Boundary-\(UUID().uuidString)"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                // Prepare form fields
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let formFields = [
                    ("event_date", dateFormatter.string(from: payload.eventDate)),
                    ("org_name", payload.orgName),
                    ("event_type", payload.eventType),
                    ("label", payload.label ?? "")
                ]
                
                let fileName = payload.fileURL.lastPathComponent
                let mimeType = mimeType(for: fileName)
                
                print("📤 Creating multipart stream...")
                let stream = try MultipartInputStream(
                    fileURL: payload.fileURL,
                    boundary: boundary,
                    formFields: formFields,
                    fileFieldName: "file",
                    fileName: fileName,
                    mimeType: mimeType
                )
                
                // Set Content-Length
                let contentLength = stream.contentLength()
                request.setValue(String(contentLength), forHTTPHeaderField: "Content-Length")
                print("🔍 Content-Length: \(ByteCountFormatter.string(fromByteCount: contentLength, countStyle: .file))")
                
                // Store stream for delegate to provide
                self.currentInputStream = stream
                
                print("📤 Starting direct stream upload...")
                let task = session.uploadTask(withStreamedRequest: request)
                self.currentUploadTask = task  // Store reference for cancellation
                
                print("🔍 Task created, state: \(task.state.rawValue)")
                task.resume()
                print("✅ Upload task resumed, state: \(task.state.rawValue)")
                print("✅ Waiting for progress callbacks and completion...")
                
                // Note: Completion will be handled by URLSessionTaskDelegate.didCompleteWithError
                // Response data accumulated in URLSessionDataDelegate.didReceive
                
            } catch {
                print("❌ Upload error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    /// Cancel the current upload task
    func cancelUpload() {
        print("🔴 [NetworkProgressUploadClient] cancelUpload() called")
        currentUploadTask?.cancel()
        // DON'T clear currentUploadTask here - the delegate callback needs to fire
        // to call the completion handler which resumes the continuation
        print("🔴 [NetworkProgressUploadClient] Cancelled task, waiting for delegate callback")
    }
    
    // MARK: - Helper Methods
    
    private func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        
        if #available(iOS 14.0, *) {
            if let type = UTType(filenameExtension: ext), 
               let mimeType = type.preferredMIMEType {
                return mimeType
            }
        }
        
        switch ext {
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4a": return "audio/m4a"
        case "mp3": return "audio/mpeg"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - URLSessionTaskDelegate (REAL Network Progress)
extension NetworkProgressUploadClient: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        // Provide the input stream for the upload
        print("🔄 Delegate needNewBodyStream called - providing MultipartInputStream")
        completionHandler(currentInputStream)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        // This is REAL network progress - bytes actually sent over the network!
        print("📊 Delegate didSendBodyData: \(totalBytesSent)/\(totalBytesExpectedToSend) bytes (\(Int((Double(totalBytesSent)/Double(totalBytesExpectedToSend))*100))%)")
        DispatchQueue.main.async {
            self.progressHandler?(totalBytesSent, totalBytesExpectedToSend)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print("🏁 Delegate didCompleteWithError called - error: \(error?.localizedDescription ?? "nil")")
        if let error = error {
            print("❌ Error details: \(error)")
            if let urlError = error as? URLError {
                print("❌ URLError code: \(urlError.code.rawValue) - \(urlError.code)")
                print("❌ URLError failureURLString: \(urlError.failureURLString ?? "none")")
            }
        }
        print("🏁 Response: \(task.response.debugDescription)")
        if let httpResponse = task.response as? HTTPURLResponse {
            print("🏁 Status code: \(httpResponse.statusCode)")
            print("🏁 Response headers: \(httpResponse.allHeaderFields)")
        } else {
            print("🏁 Status code: -1 (no HTTP response)")
        }
        
        DispatchQueue.main.async {
            if let error = error {
                // Task failed or was cancelled
                print("❌ Completing with error: \(error.localizedDescription)")
                print("❌ Response data received before error: \(self.responseData.count) bytes")
                if self.responseData.count > 0 {
                    if let responseText = String(data: self.responseData, encoding: .utf8) {
                        print("❌ Response body: \(responseText)")
                    }
                }
                self.completion?(.failure(error))
            } else {
                // Task completed successfully - return accumulated response data
                let status = (task.response as? HTTPURLResponse)?.statusCode ?? -1
                let requestURL = task.originalRequest?.url ?? self.baseURL
                print("✅ Completing with success - status: \(status), data size: \(self.responseData.count) bytes")
                if let responseText = String(data: self.responseData, encoding: .utf8) {
                    print("✅ Response body: \(responseText)")
                }
                self.completion?(.success((status: status, data: self.responseData, requestURL: requestURL)))
            }
            
            // Clear state
            self.responseData = Data()
            self.completion = nil
            self.progressHandler = nil
            self.currentUploadTask = nil  // Clear task reference after completion
        }
    }
}

// MARK: - URLSessionDataDelegate
extension NetworkProgressUploadClient: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        print("📥 Delegate didReceive response called")
        if let httpResponse = response as? HTTPURLResponse {
            print("📥 Early response status: \(httpResponse.statusCode)")
            print("📥 Early response headers: \(httpResponse.allHeaderFields)")
            
            // Check if we're getting an error response early
            if httpResponse.statusCode >= 400 {
                print("⚠️ Server returned error status \(httpResponse.statusCode) before upload completed!")
                
                // Special handling for 413 - Cloudflare upload limit
                if httpResponse.statusCode == 413 {
                    print("🚫 HTTP 413: Cloudflare 100MB upload limit exceeded!")
                    print("🚫 This upload will be aborted by the server")
                }
            }
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Accumulate response data (can be called multiple times)
        // Completion will be called in didCompleteWithError with all accumulated data
        print("📥 Delegate didReceive data: \(data.count) bytes (total accumulated: \(self.responseData.count + data.count) bytes)")
        if let partial = String(data: data, encoding: .utf8) {
            print("📥 Partial response: \(partial)")
        }
        self.responseData.append(data)
    }
}

/// Combined delegate for handling both insecure trust and progress tracking
class InsecureTrustUploadDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    private weak var uploadClient: NetworkProgressUploadClient?
    
    init(uploadClient: NetworkProgressUploadClient) {
        self.uploadClient = uploadClient
    }
    
    // Handle insecure trust challenges (same as InsecureTrustDelegate)
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Accept any certificate (insecure mode)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            let credential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    // Forward stream request to NetworkProgressUploadClient
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        uploadClient?.urlSession(session, task: task, needNewBodyStream: completionHandler)
    }
    
    // Forward progress to NetworkProgressUploadClient
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        uploadClient?.urlSession(session, task: task, didSendBodyData: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        uploadClient?.urlSession(session, task: task, didCompleteWithError: error)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        uploadClient?.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        uploadClient?.urlSession(session, dataTask: dataTask, didReceive: data)
    }
}
