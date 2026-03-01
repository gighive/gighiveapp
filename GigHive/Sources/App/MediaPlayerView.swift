import SwiftUI
import AVKit
import AVFoundation

struct PlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        logWithTimestamp("[PlayerVC] makeUIViewController called")
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.showsPlaybackControls = true
        controller.delegate = context.coordinator
        logWithTimestamp("[PlayerVC] Created controller with player=\(player)")
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        let currentTime = uiViewController.player?.currentTime().seconds ?? -1
        let rate = uiViewController.player?.rate ?? -1
        logWithTimestamp("[PlayerVC] updateUIViewController called - currentTime=\(currentTime) rate=\(rate)")
        if uiViewController.player !== player {
            logWithTimestamp("[PlayerVC] ⚠️ Player instance changed, updating (this should NOT happen)")
            uiViewController.player = player
        } else {
            logWithTimestamp("[PlayerVC] ✅ Player instance is the same, no update needed")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        func playerViewController(_ playerViewController: AVPlayerViewController, willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            let currentTime = playerViewController.player?.currentTime().seconds ?? -1
            let rate = playerViewController.player?.rate ?? -1
            logWithTimestamp("[PlayerVC] 🔲 Will BEGIN fullscreen presentation - time=\(currentTime) rate=\(rate)")
        }
        
        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            let currentTime = playerViewController.player?.currentTime().seconds ?? -1
            let rate = playerViewController.player?.rate ?? -1
            logWithTimestamp("[PlayerVC] 🔲 Will END fullscreen presentation - time=\(currentTime) rate=\(rate)")
        }
    }
}

struct MediaPlayerView: View {
    let baseURL: URL
    let entry: MediaEntry
    let credentials: (user: String, pass: String)?
    let allowInsecureTLS: Bool

    @Environment(\.presentationMode) private var presentationMode
    @State private var player: AVPlayer? = nil
    @State private var errorMessage: String? = nil
    @State private var statusObserver: NSKeyValueObservation? = nil
    @State private var timeObserverToken: Any? = nil
    @State private var timeControlObserver: NSKeyValueObservation? = nil
    @State private var loaderRef: MediaResourceLoader? = nil
    @State private var hasAutoPlayed: Bool = false

    var body: some View {
        NavigationView {
            Group {
                if let player = player {
                    PlayerViewController(player: player)
                        .onAppear {
                            if !hasAutoPlayed {
                                logWithTimestamp("[Player] PlayerViewController appeared; starting playback")
                                player.play()
                                hasAutoPlayed = true
                            } else {
                                logWithTimestamp("[Player] PlayerViewController appeared; skipping autoplay (already played)")
                            }
                        }
                } else if let error = errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Playback failed").foregroundColor(.red)
                        Text(error).font(.caption)
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading media…").foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle(entry.songTitle.isEmpty ? (entry.fileType == "video" ? "Play Video" : "Play Audio") : entry.songTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { close() }
                }
            }
        }
        .onAppear {
            // Ensure audio plays even in silent mode
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                logWithTimestamp("[Player] AudioSession error: \\(error.localizedDescription)")
            }
            // Only prepare player once
            if player == nil {
                Task { await preparePlayer() }
            } else {
                logWithTimestamp("[Player] MediaPlayerView appeared; player already initialized, skipping preparePlayer")
            }
        }
        .ghFullScreenBackground(GHTheme.bg)
    }

    private func close() {
        logWithTimestamp("[Player] Close tapped")
        cleanup()
        presentationMode.wrappedValue.dismiss()
    }
    
    private func cleanup() {
        logWithTimestamp("[Player] Cleaning up player resources")
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        NotificationCenter.default.removeObserver(self)
        player = nil
        loaderRef = nil
    }

    private func preparePlayer() async {
        do {
            guard let mediaURL = URL(string: entry.url, relativeTo: baseURL) else {
                errorMessage = "Invalid media URL"
                logWithTimestamp("[Player] Invalid media URL for file=\(entry.fileName)")
                return
            }
            logWithTimestamp("[Player] Media URL components: scheme=\(mediaURL.scheme ?? "<nil>") host=\(mediaURL.host ?? "<nil>") path=\(mediaURL.path)")
            var headers: [String: String] = [:]
            if let creds = credentials {
                let token = Data("\(creds.user):\(creds.pass)".utf8).base64EncodedString()
                headers["Authorization"] = "Basic \(token)"
            }
            logWithTimestamp("[Player] Building AVURLAsset; url=\(mediaURL.absoluteString); auth=\(headers["Authorization"] != nil); insecureTLS=\(allowInsecureTLS)")

            // VERBOSE: Preflight HEAD request to inspect HTTP status and headers
            await headDiagnostics(url: mediaURL, headers: headers)

            let asset: AVURLAsset
            if allowInsecureTLS {
                // Route through resource loader proxy with custom scheme (explicit build)
                let host = mediaURL.host ?? ""
                let port = mediaURL.port.map { ":\($0)" } ?? ""
                let path = mediaURL.path
                let query = mediaURL.query.map { "?\($0)" } ?? ""
                logWithTimestamp("[Player] Proxy parts host=\(host) port=\(port) path=\(path) query=\(query)")
                let customString = "gighive://\(host)\(port)\(path)\(query)"
                guard let custom = URL(string: customString) else {
                    logWithTimestamp("[Player] Proxy URL build failed string=\(customString)")
                    errorMessage = "Unsupported media URL"
                    return
                }
                logWithTimestamp("[Player] Proxy custom URL=\(custom.absoluteString) (host=\(host), port=\(port), path=\(path))")
                let loader = MediaResourceLoader(allowInsecureTLS: allowInsecureTLS, credentials: credentials)
                self.loaderRef = loader // retain strongly for the life of this view
                asset = AVURLAsset(url: custom)
                asset.resourceLoader.setDelegate(loader, queue: .main)
                logWithTimestamp("[Player] Using proxy loader for media")
            } else {
                // Direct path with Authorization header for valid TLS
                asset = AVURLAsset(url: mediaURL, options: [
                    "AVURLAssetHTTPHeaderFieldsKey": headers
                ])
            }
            let item = AVPlayerItem(asset: asset)

            // Observe status changes for debugging
            NotificationCenter.default.addObserver(forName: .AVPlayerItemNewAccessLogEntry, object: item, queue: .main) { _ in
                if let logs = item.accessLog()?.events, let last = logs.last {
                    let fields: [String: Any] = [
                        "uri": last.uri ?? "<nil>",
                        "numberOfMediaRequests": last.numberOfMediaRequests,
                        "playbackStartDate": last.playbackStartDate?.description ?? "<nil>",
                        "playbackStartOffset": last.playbackStartOffset,
                        "observedBitrate": last.observedBitrate,
                        "indicatedBitrate": last.indicatedBitrate,
                        "numberOfBytesTransferred": last.numberOfBytesTransferred,
                        "transferDuration": last.transferDuration,
                        "mediaRequestsWWAN": last.mediaRequestsWWAN
                    ]
                    logWithTimestamp("[Player] AccessLog: \(fields)")
                } else {
                    logWithTimestamp("[Player] Access log entry (no details)")
                }
            }
            NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { note in
                let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?.localizedDescription ?? "unknown"
                logWithTimestamp("[Player] Failed to play: \(err)")
                self.errorMessage = err
            }
            NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { _ in
                logWithTimestamp("[Player] Playback stalled for \(self.entry.fileName)")
            }

            // KVO for item.status
            statusObserver = item.observe(\.status, options: [.initial, .new]) { _, change in
                switch item.status {
                case .unknown:
                    logWithTimestamp("[Player] Item status: unknown")
                case .readyToPlay:
                    logWithTimestamp("[Player] Item status: readyToPlay")
                case .failed:
                    let err = item.error?.localizedDescription ?? "unknown"
                    logWithTimestamp("[Player] Item status: failed: \(err)")
                    self.errorMessage = err
                @unknown default:
                    logWithTimestamp("[Player] Item status: unknown default")
                }
            }

            let newPlayer = AVPlayer(playerItem: item)
            self.player = newPlayer

            // Observe timeControlStatus to know when playback starts/waits
            timeControlObserver = newPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
                let currentTime = player.currentTime().seconds
                let rate = player.rate
                switch player.timeControlStatus {
                case .paused:
                    logWithTimestamp("[Player] ⏸️ timeControlStatus=paused rate=\(rate) time=\(currentTime)")
                case .waitingToPlayAtSpecifiedRate:
                    let reason = player.reasonForWaitingToPlay?.rawValue ?? "<nil>"
                    logWithTimestamp("[Player] ⏳ timeControlStatus=waiting (reason=\(reason)) rate=\(rate) time=\(currentTime)")
                case .playing:
                    logWithTimestamp("[Player] ▶️ timeControlStatus=playing rate=\(rate) time=\(currentTime)")
                @unknown default:
                    logWithTimestamp("[Player] ❓ timeControlStatus=unknown rate=\(rate) time=\(currentTime)")
                }
            }
            
            // Observe rate changes directly
            let rateObserver = newPlayer.observe(\.rate, options: [.old, .new]) { player, change in
                let oldRate = change.oldValue ?? 0.0
                let newRate = change.newValue ?? 0.0
                let currentTime = player.currentTime().seconds
                logWithTimestamp("[Player] 🎚️ Rate changed: \(oldRate) -> \(newRate) at time=\(currentTime)")
            }
            // Store the rate observer (we need to add a state variable for this)
            self.statusObserver = rateObserver

            // Add a short timeout to report if playback does not become ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.errorMessage == nil, item.status != .readyToPlay {
                    logWithTimestamp("[Player] Still not ready after 3s; possible TLS/ATS or auth issue")
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            logWithTimestamp("[Player] Error: \(error.localizedDescription)")
        }
    }

    private func headDiagnostics(url: URL, headers: [String: String]) async {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        headers.forEach { k, v in request.setValue(v, forHTTPHeaderField: k) }
        let cfg = URLSessionConfiguration.ephemeral
        let session: URLSession = allowInsecureTLS ? URLSession(configuration: cfg, delegate: InsecureTrustDelegate.shared, delegateQueue: nil) : URLSession(configuration: cfg)
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                let ct = http.value(forHTTPHeaderField: "Content-Type") ?? "<nil>"
                let cl = http.value(forHTTPHeaderField: "Content-Length") ?? "<nil>"
                let ar = http.value(forHTTPHeaderField: "Accept-Ranges") ?? "<nil>"
                logWithTimestamp("[Player][HEAD] status=\(http.statusCode) CT=\(ct) CL=\(cl) Accept-Ranges=\(ar)")
            } else {
                logWithTimestamp("[Player][HEAD] Non-HTTP response")
            }
        } catch {
            logWithTimestamp("[Player][HEAD] Error: \(error.localizedDescription)")
        }
    }
}
