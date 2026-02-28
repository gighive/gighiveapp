import Foundation
import UniformTypeIdentifiers
import TUSKit

final class TUSUploadClient {
    private let tusBaseURL: URL
    private let basicAuth: (user: String, pass: String)?
    private let chunkSize: Int

    private let tusClient: TUSClient
    private let delegateProxy: DelegateProxy
    private var currentUploadID: UUID?

    init(tusBaseURL: URL, basicAuth: (user: String, pass: String)?, allowInsecure: Bool, chunkSize: Int = 5 * 1024 * 1024) throws {
        self.tusBaseURL = tusBaseURL
        self.basicAuth = basicAuth
        self.chunkSize = chunkSize

        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = true
        cfg.allowsExpensiveNetworkAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 600
        cfg.multipathServiceType = .none
        cfg.httpShouldUsePipelining = false
        cfg.httpMaximumConnectionsPerHost = 1
        if #available(iOS 15.0, *) {
            cfg.assumesHTTP3Capable = false
        }

        let session: URLSession
        if allowInsecure {
            session = URLSession(configuration: cfg, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
        } else {
            session = URLSession(configuration: cfg)
        }

        let delegateProxy = DelegateProxy()
        self.delegateProxy = delegateProxy
        self.tusClient = try TUSClient(
            server: tusBaseURL,
            sessionIdentifier: "GigHiveTUS",
            storageDirectory: URL(string: "TUS"),
            session: session,
            chunkSize: chunkSize,
            supportedExtensions: [.creation],
            reportingQueue: DispatchQueue.main,
            generateHeaders: { [basicAuth] _, headers, completion in
                var mutated = headers
                if let basicAuth {
                    let credentials = "\(basicAuth.user):\(basicAuth.pass)"
                    let encoded = Data(credentials.utf8).base64EncodedString()
                    mutated["Authorization"] = "Basic \(encoded)"
                }
                completion(mutated)
            }
        )
        self.tusClient.delegate = delegateProxy
        _ = self.tusClient.start()
    }

    func cancel() {
        delegateProxy.completeCancelledIfNeeded()
        if let id = currentUploadID {
            do {
                try tusClient.cancelAndDelete(id: id)
            } catch {
                try? tusClient.cancel(id: id)
            }
        } else {
            tusClient.stopAndCancelAll()
        }
    }

    func uploadFile(payload: UploadPayload, progress: ((Int64, Int64) -> Void)? = nil) async throws -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var context: [String: String] = [
            "event_date": df.string(from: payload.eventDate),
            "org_name": payload.orgName,
            "event_type": payload.eventType
        ]
        if let label = payload.label {
            context["label"] = label
        }
        if let participants = payload.participants { context["participants"] = participants }
        if let keywords = payload.keywords { context["keywords"] = keywords }
        if let location = payload.location { context["location"] = location }
        if let rating = payload.rating { context["rating"] = rating }
        if let notes = payload.notes { context["notes"] = notes }

        return try await withCheckedThrowingContinuation { continuation in
            delegateProxy.configureForSingleUpload(progress: progress) { result in
                continuation.resume(with: result)
            }

            do {
                let id = try tusClient.uploadFileAt(filePath: payload.fileURL, uploadURL: tusBaseURL, customHeaders: [:], context: context)
                self.currentUploadID = id
            } catch {
                delegateProxy.clearSingleUpload()
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class DelegateProxy: NSObject, TUSClientDelegate {
    private var progress: ((Int64, Int64) -> Void)?
    private var completion: ((Result<URL, Error>) -> Void)?
    private let lock = NSLock()
    private var didComplete: Bool = false

    func configureForSingleUpload(progress: ((Int64, Int64) -> Void)?, completion: @escaping (Result<URL, Error>) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        didComplete = false
        self.progress = progress
        self.completion = completion
    }

    func clearSingleUpload() {
        lock.lock()
        defer { lock.unlock() }
        self.progress = nil
        self.completion = nil
        didComplete = false
    }

    func completeCancelledIfNeeded() {
        complete(.failure(CancellationError()))
    }

    private func complete(_ result: Result<URL, Error>) {
        lock.lock()
        if didComplete {
            lock.unlock()
            return
        }
        didComplete = true
        let completion = self.completion
        lock.unlock()

        completion?(result)
        clearSingleUpload()
    }

    func didStartUpload(id: UUID, context: [String : String]?, client: TUSClient) {
        // no-op
    }

    func didFinishUpload(id: UUID, url: URL, context: [String : String]?, client: TUSClient) {
        complete(.success(url))
    }

    func uploadFailed(id: UUID, error: Error, context: [String : String]?, client: TUSClient) {
        complete(.failure(error))
    }

    func fileError(error: TUSClientError, client: TUSClient) {
        complete(.failure(error))
    }

    @available(iOS 11.0, macOS 10.13, watchOS 6.0, *)
    func totalProgress(bytesUploaded: Int, totalBytes: Int, client: TUSClient) {
        // no-op
    }

    @available(iOS 11.0, macOS 10.13, watchOS 6.0, *)
    func progressFor(id: UUID, context: [String : String]?, bytesUploaded: Int, totalBytes: Int, client: TUSClient) {
        progress?(Int64(bytesUploaded), Int64(totalBytes))
    }
}
