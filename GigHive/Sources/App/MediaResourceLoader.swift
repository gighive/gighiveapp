import Foundation
import AVFoundation
import UniformTypeIdentifiers

final class MediaResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {
    private static let errorDomain = "GigHiveMediaResourceLoader"
    private let allowInsecureTLS: Bool
    private let credentials: (user: String, pass: String)?
    private(set) var lastFailureMessage: String?
    private(set) var lastFailureResponseHeaders: [AnyHashable: Any] = [:]
    private final class RequestState {
        let loadingRequest: AVAssetResourceLoadingRequest
        let session: URLSession
        var finished: Bool = false
        var requestedOffset: Int64 = 0
        var requestedLength: Int64 = 0 // 0 means open-ended
        var bytesDelivered: Int64 = 0
        init(_ req: AVAssetResourceLoadingRequest, session: URLSession) {
            self.loadingRequest = req
            self.session = session
        }
    }
    private var tasks: [URLSessionTask: RequestState] = [:]
    private let queue = DispatchQueue(label: "com.gighive.media.loader")

    init(allowInsecureTLS: Bool, credentials: (user: String, pass: String)?) {
        self.allowInsecureTLS = allowInsecureTLS
        self.credentials = credentials
    }

    // Map custom scheme gighive back to https
    private func realURL(from url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if comps.scheme == "gighive" {
            comps.scheme = "https"
            return comps.url
        }
        return url
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        queue.async { [weak self] in self?.start(loadingRequest) }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        queue.async { [weak self] in self?.cancel(loadingRequest) }
    }

    private func start(_ loadingRequest: AVAssetResourceLoadingRequest) {
        guard let url = loadingRequest.request.url, let real = realURL(from: url) else {
            loadingRequest.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL, userInfo: nil))
            return
        }
        logWithTimestamp("[Loader] Intercepted URL=\(url.absoluteString) -> real=\(real.absoluteString)")

        var req = URLRequest(url: real)
        req.httpMethod = "GET"

        // Range support
        if let dataReq = loadingRequest.dataRequest {
            let start = dataReq.requestedOffset
            let length = Int64(dataReq.requestedLength)
            if length > 0 {
                let end = start + length - 1
                req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
            } else {
                req.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
            }
        }

        if let creds = credentials {
            let token = Data("\(creds.user):\(creds.pass)".utf8).base64EncodedString()
            req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }

        let cfg = URLSessionConfiguration.ephemeral
        let opQueue = OperationQueue()
        opQueue.maxConcurrentOperationCount = 1
        opQueue.underlyingQueue = queue
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: opQueue)
        logWithTimestamp("[Loader] GET \(real.absoluteString) headers=\(req.allHTTPHeaderFields ?? [:])")
        let task = session.dataTask(with: req)
        let state = RequestState(loadingRequest, session: session)
        if let dataReq = loadingRequest.dataRequest {
            state.requestedOffset = dataReq.requestedOffset
            state.requestedLength = Int64(dataReq.requestedLength)
        }
        tasks[task] = state
        task.resume()
    }

    private func cancel(_ loadingRequest: AVAssetResourceLoadingRequest) {
        if let entry = tasks.first(where: { $0.value.loadingRequest == loadingRequest }) {
            let task = entry.key
            if let state = tasks.removeValue(forKey: task) {
                if !state.finished {
                    state.finished = true
                    task.cancel()
                    state.session.invalidateAndCancel()
                    logWithTimestamp("[Loader] Cancelled request for \(loadingRequest.request.url?.absoluteString ?? "<nil>")")
                }
            }
        }
    }

    // MARK: - URLSession Delegate (TLS bypass)
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if allowInsecureTLS,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    // MARK: - URLSession Data Delegate
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let state = tasks[dataTask] else { completionHandler(.cancel); return }
        if state.finished { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        logWithTimestamp("[Loader] HTTP \(http.statusCode) for \(dataTask.currentRequest?.url?.path ?? "<nil>")")
        let requestedRange = state.requestedOffset > 0 || state.requestedLength > 0
        if !(200...299).contains(http.statusCode) {
            state.finished = true
            state.loadingRequest.finishLoading(with: NSError(domain: NSURLErrorDomain, code: http.statusCode, userInfo: nil))
            state.session.invalidateAndCancel()
            tasks.removeValue(forKey: dataTask)
            completionHandler(.cancel)
            return
        }
        if requestedRange && http.statusCode != 206 {
            state.finished = true
            let message = "Server did not honor byte-range request for media playback. Expected HTTP 206 Partial Content but received HTTP \(http.statusCode)."
            lastFailureMessage = message
            lastFailureResponseHeaders = http.allHeaderFields
            logWithTimestamp("[Loader] ❌ \(message)")
            // Dump all response headers for root-cause diagnosis
            let diagHeaders = ["cf-cache-status", "server", "content-length", "content-range",
                               "accept-ranges", "cache-control", "etag", "x-cache", "via", "age"]
            for key in diagHeaders {
                if let val = http.value(forHTTPHeaderField: key) {
                    logWithTimestamp("[Loader] ⚠️ resp[\(key)]=\(val)")
                }
            }
            logWithTimestamp("[Loader] ⚠️ allHeaders=\(http.allHeaderFields as? [String: Any] ?? [:])")
            logWithTimestamp("[Loader] ⚠️ requestedRange=bytes=\(state.requestedOffset)-\(state.requestedOffset + state.requestedLength - 1) url=\(dataTask.currentRequest?.url?.absoluteString ?? "<nil>")")
            logWithTimestamp("[Loader] ⚠️ requestURL headers=\(dataTask.currentRequest?.allHTTPHeaderFields ?? [:])")
            logWithTimestamp("[Loader] ⚠️ originalURL headers=\(dataTask.originalRequest?.allHTTPHeaderFields ?? [:])")
            logWithTimestamp("[Loader] ⚠️ response URL=\(http.url?.absoluteString ?? "<nil>")")
            logWithTimestamp("[Loader] ⚠️ HTTP version (expectedContentLength)=\(http.expectedContentLength)")
            state.loadingRequest.finishLoading(with: NSError(
                domain: Self.errorDomain,
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
            state.session.invalidateAndCancel()
            tasks.removeValue(forKey: dataTask)
            completionHandler(.cancel)
            return
        }
        if let info = state.loadingRequest.contentInformationRequest {
            info.isByteRangeAccessSupported = (http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") == true)
            // Determine content length
            if let cr = http.value(forHTTPHeaderField: "Content-Range"),
               let totalStr = cr.split(separator: "/").last, let total = Int64(totalStr) {
                info.contentLength = total
            } else if let cl = http.value(forHTTPHeaderField: "Content-Length"), let sz = Int64(cl) {
                info.contentLength = sz
            }
            // UTI mapping
            if let mime = http.value(forHTTPHeaderField: "Content-Type"),
               let utType = UTType(mimeType: mime) {
                info.contentType = utType.identifier
            } else if let ext = dataTask.currentRequest?.url?.pathExtension, let utType = UTType(filenameExtension: ext) {
                info.contentType = utType.identifier
            }
        }
        if state.loadingRequest.dataRequest == nil {
            state.finished = true
            state.loadingRequest.finishLoading()
            state.session.invalidateAndCancel()
            tasks.removeValue(forKey: dataTask)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let state = tasks[dataTask], !state.finished, let dataReq = state.loadingRequest.dataRequest else { return }
        dataReq.respond(with: data)
        state.bytesDelivered += Int64(data.count)
        // If AVPlayer requested a fixed length, finish once satisfied
        if state.requestedLength > 0, state.bytesDelivered >= state.requestedLength {
            state.finished = true
            state.loadingRequest.finishLoading()
            dataTask.cancel()
            state.session.invalidateAndCancel()
            tasks.removeValue(forKey: dataTask)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let state = tasks.removeValue(forKey: task) else { return }
        if state.finished { return }
        state.finished = true
        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled {
                logWithTimestamp("[Loader] Complete cancelled (expected)")
            } else {
                logWithTimestamp("[Loader] Complete with error: \(error.localizedDescription)")
                state.loadingRequest.finishLoading(with: error)
            }
        } else {
            state.loadingRequest.finishLoading()
        }
        state.session.finishTasksAndInvalidate()
    }
}
