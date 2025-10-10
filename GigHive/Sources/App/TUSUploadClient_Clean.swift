import Foundation
import UniformTypeIdentifiers

/// Clean, simplified upload client - DEPRECATED
/// Use NetworkProgressUploadClient instead for real network progress tracking
final class TUSUploadClient_Clean {
    private let baseURL: URL
    private let basicAuth: (user: String, pass: String)?
    private let allowInsecure: Bool
    private var networkClient: NetworkProgressUploadClient?
    
    init(baseURL: URL, basicAuth: (String, String)?, allowInsecure: Bool) {
        self.baseURL = baseURL
        self.basicAuth = basicAuth
        self.allowInsecure = allowInsecure
    }
    
    /// Simple upload method - delegates to NetworkProgressUploadClient for real progress
    func uploadFile(
        payload: UploadPayload,
        progressHandler: @escaping (Int64, Int64) -> Void,
        completion: @escaping (Result<(status: Int, data: Data, requestURL: URL), Error>) -> Void
    ) {
        NSLog("🔵 TUSUploadClient_Clean.uploadFile() called for: %@", payload.fileURL.lastPathComponent)
        print("🔵 TUSUploadClient_Clean.uploadFile() called for: \(payload.fileURL.lastPathComponent)")
        
        // Use the new NetworkProgressUploadClient for real network progress tracking
        let networkClient = NetworkProgressUploadClient(
            baseURL: baseURL,
            basicAuth: basicAuth,
            allowInsecure: allowInsecure
        )
        self.networkClient = networkClient  // Store reference for cancellation
        
        NSLog("🔵 Calling NetworkProgressUploadClient.uploadFile()...")
        print("🔵 Calling NetworkProgressUploadClient.uploadFile()...")
        networkClient.uploadFile(
            payload: payload,
            progressHandler: progressHandler,
            completion: completion
        )
        NSLog("🔵 NetworkProgressUploadClient.uploadFile() call completed (async)")
        print("🔵 NetworkProgressUploadClient.uploadFile() call completed (async)")
    }
    
    /// Cancel the current upload
    func cancelUpload() {
        print("🔴 [TUSUploadClient_Clean] cancelUpload() called")
        networkClient?.cancelUpload()
        // DON'T clear networkClient here - it needs to stay alive to fire the completion callback
        // which will resume the continuation. It will be cleared when the completion fires.
        print("🔴 [TUSUploadClient_Clean] cancelUpload() completed - networkClient still alive for callback")
    }
}
