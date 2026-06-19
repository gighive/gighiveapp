import SwiftUI
import AVKit
import AVFoundation
import UIKit

final class AudioPlaybackState: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTimeSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var scrubPositionSeconds: Double = 0
    @Published var isScrubbing: Bool = false

    @MainActor
    func reset() {
        isPlaying = false
        currentTimeSeconds = 0
        durationSeconds = 0
        scrubPositionSeconds = 0
        isScrubbing = false
    }
}

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
    private enum PlaybackOverlayState: Equatable {
        case loading(String)
        case failed(title: String, detail: String)
        case none
    }

    let baseURL: URL
    let entry: MediaEntry
    let credentials: (user: String, pass: String)?
    let allowInsecureTLS: Bool

    @Environment(\.presentationMode) private var presentationMode
    @State private var player: AVPlayer? = nil
    @State private var errorMessage: String? = nil
    @State private var itemStatusObserver: NSKeyValueObservation? = nil
    @State private var likelyToKeepUpObserver: NSKeyValueObservation? = nil
    @State private var bufferEmptyObserver: NSKeyValueObservation? = nil
    @State private var bufferFullObserver: NSKeyValueObservation? = nil
    @State private var timeObserverToken: Any? = nil
    @State private var timeControlObserver: NSKeyValueObservation? = nil
    @State private var rateObserver: NSKeyValueObservation? = nil
    @State private var loaderRef: MediaResourceLoader? = nil
    @State private var hasAutoPlayed: Bool = false
    @State private var overlayState: PlaybackOverlayState = .loading("Loading media…")
    @StateObject private var audioState = AudioPlaybackState()

    private var isVideo: Bool {
        entry.fileType == "video"
    }


    var body: some View {
        Group {
            if isVideo {
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
                                .overlay(overlayContent)
                        } else {
                            overlayContent
                        }
                    }
                    .navigationTitle(entry.songTitle.isEmpty ? "Play Video" : entry.songTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close") { close() }
                        }
                    }
                }
            } else {
                audioRootContent
            }
        }
        .onAppear {
            if isVideo {
                configureNavigationBarAppearance()
            }
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
        .onDisappear {
            if isVideo {
                resetNavigationBarAppearance()
            }
        }
        .ghFullScreenBackground(GHTheme.bg)
    }

    @ViewBuilder
    private var audioRootContent: some View {
        NavigationView {
            VStack(spacing: 0) {
                Group {
                    if let player = player {
                        audioPlayerContent(player: player)
                            .onAppear {
                                if case .loading = overlayState {
                                    overlayState = .none
                                    logAudioUIState(prefix: "[AudioUI] cleared loading on appear")
                                }
                            }
                        if case .failed = overlayState {
                            overlayContent
                        }
                    } else {
                        overlayContent
                    }
                }
            }
            .navigationTitle(entry.songTitle.isEmpty ? "Play Audio" : entry.songTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        logWithTimestamp("[AudioUI] NavBar Close tapped")
                        close()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        likelyToKeepUpObserver?.invalidate()
        likelyToKeepUpObserver = nil
        bufferEmptyObserver?.invalidate()
        bufferEmptyObserver = nil
        bufferFullObserver?.invalidate()
        bufferFullObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        NotificationCenter.default.removeObserver(self)
        player = nil
        loaderRef = nil
        Task { @MainActor in
            audioState.reset()
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch overlayState {
        case .loading(let message):
            VStack(spacing: 12) {
                ProgressView()
                Text(message).foregroundColor(.orange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(player == nil ? 0 : 0.45))
            .allowsHitTesting(false)
        case .failed(let title, let detail):
            VStack(alignment: .center, spacing: 10) {
                Text(title)
                    .foregroundColor(.red)
                Text(detail)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.55))
            .allowsHitTesting(false)
        case .none:
            EmptyView()
        }
    }


    private func audioPlayerContent(player: AVPlayer) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: audioState.isPlaying ? "waveform.circle.fill" : "music.note")
                .font(.system(size: 88))
                .foregroundColor(.white)
            Text(entry.songTitle.isEmpty ? entry.fileName : entry.songTitle)
                .font(.title3)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let message = audioStatusMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            VStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { audioState.isScrubbing ? audioState.scrubPositionSeconds : audioState.currentTimeSeconds },
                        set: { newValue in
                            audioState.scrubPositionSeconds = newValue
                        }
                    ),
                    in: 0...max(audioState.durationSeconds, 1),
                    onEditingChanged: { editing in
                        if editing {
                            audioState.isScrubbing = true
                            audioState.scrubPositionSeconds = audioState.currentTimeSeconds
                            logWithTimestamp("[Audio] Started scrubbing at time=\(audioState.currentTimeSeconds)")
                        } else {
                            seekAudio(to: audioState.scrubPositionSeconds, player: player)
                        }
                    }
                )
                .accentColor(.white)
                HStack {
                    Text(formattedTime(audioState.isScrubbing ? audioState.scrubPositionSeconds : audioState.currentTimeSeconds))
                    Spacer()
                    Text(formattedTime(audioState.durationSeconds))
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 24)
            HStack(spacing: 24) {
                Button(action: {
                    logAudioUIState(prefix: "[AudioUI] Restart tapped")
                    seekAudio(to: 0, player: player)
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())
                Button(action: {
                    logAudioUIState(prefix: "[AudioUI] PlayPause tapped")
                    togglePlayback(for: player)
                }) {
                    Image(systemName: audioState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())
                if audioState.currentTimeSeconds <= 0.1 && !audioState.isPlaying {
                    Button(action: {
                        retryAudioPlayback(player: player)
                    }) {
                        Text("Retry")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.14))
                            .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .contentShape(Rectangle())
        .zIndex(1)
        .onAppear {
            logAudioUIState(prefix: "[AudioUI] audioPlayerContent appeared")
        }
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = .white
    }

    private func resetNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = nil
    }

    private func showLoading(_ message: String = "Loading media…") {
        errorMessage = nil
        overlayState = .loading(message)
    }

    private func showFailure(_ message: String, title: String = "Media failed to load") {
        errorMessage = message
        overlayState = .failed(title: title, detail: message)
    }

    private var audioStatusMessage: String? {
        if let errorMessage {
            return errorMessage
        }
        switch overlayState {
        case .loading(let message):
            return message
        case .failed(_, let detail):
            return detail
        case .none:
            if player != nil, audioState.currentTimeSeconds <= 0.1, !audioState.isPlaying {
                return "Audio is preparing. You can tap Retry or Close."
            }
            return nil
        }
    }

    private func togglePlayback(for player: AVPlayer) {
        if audioState.isPlaying {
            logWithTimestamp("[Audio] Pause tapped at time=\(audioState.currentTimeSeconds)")
            player.pause()
        } else {
            logWithTimestamp("[Audio] Play tapped at time=\(audioState.currentTimeSeconds)")
            player.play()
        }
    }

    private func retryAudioPlayback(player: AVPlayer) {
        logAudioUIState(prefix: "[Audio] Retry tapped")
        player.play()
    }

    private func seekAudio(to seconds: Double, player: AVPlayer) {
        let boundedSeconds = min(max(seconds, 0), max(audioState.durationSeconds, 0))
        logWithTimestamp("[Audio] Seeking to time=\(boundedSeconds)")
        let target = CMTime(seconds: boundedSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                self.audioState.currentTimeSeconds = boundedSeconds
                self.audioState.scrubPositionSeconds = boundedSeconds
                self.audioState.isScrubbing = false
                logWithTimestamp("[Audio] Seek completed at time=\(boundedSeconds)")
            }
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func logAudioUIState(prefix: String) {
        logWithTimestamp("\(prefix) isPlaying=\(audioState.isPlaying) current=\(audioState.currentTimeSeconds) duration=\(audioState.durationSeconds) scrub=\(audioState.scrubPositionSeconds) isScrubbing=\(audioState.isScrubbing) overlay=\(String(describing: overlayState)) playerExists=\(player != nil)")
    }

    private func preparePlayer() async {
            showLoading()
            guard let mediaURL = URL(string: entry.url, relativeTo: baseURL) else {
                showFailure("Invalid media URL")
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
            let shouldUseProxyLoader = allowInsecureTLS || !headers.isEmpty
            if shouldUseProxyLoader {
                // Route through resource loader proxy with custom scheme so AVFoundation
                // does not depend on direct header-field handling for authenticated media.
                let host = mediaURL.host ?? ""
                let port = mediaURL.port.map { ":\($0)" } ?? ""
                let path = mediaURL.path
                let query = mediaURL.query.map { "?\($0)" } ?? ""
                logWithTimestamp("[Player] Proxy parts host=\(host) port=\(port) path=\(path) query=\(query)")
                let customString = "gighive://\(host)\(port)\(path)\(query)"
                guard let custom = URL(string: customString) else {
                    logWithTimestamp("[Player] Proxy URL build failed string=\(customString)")
                    showFailure("Unsupported media URL")
                    return
                }
                logWithTimestamp("[Player] Proxy custom URL=\(custom.absoluteString) (host=\(host), port=\(port), path=\(path))")
                let loader = MediaResourceLoader(allowInsecureTLS: allowInsecureTLS, credentials: credentials)
                self.loaderRef = loader // retain strongly for the life of this view
                asset = AVURLAsset(url: custom)
                asset.resourceLoader.setDelegate(loader, queue: .main)
                logWithTimestamp("[Player] Using proxy loader for media")
            } else {
                // Direct path for public media when no custom loading behavior is needed
                asset = AVURLAsset(url: mediaURL, options: [
                    "AVURLAssetHTTPHeaderFieldsKey": headers
                ])
            }

            // NOTE: Do NOT call logAssetDiagnostics before creating the player item.
            // loadValuesAsynchronously permanently caches key-load failures, which
            // poisons the asset before AVPlayerItem/AVPlayer get a chance to load it
            // using their own internal recovery logic.
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
                self.showFailure(err)
            }
            NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { _ in
                self.logItemDiagnostics(item, prefix: "[Player] Playback stalled")
                if self.errorMessage == nil {
                    self.showLoading("Buffering video...")
                }
            }

            let newPlayer = AVPlayer(playerItem: item)
            self.player = newPlayer
            if !self.isVideo {
                self.overlayState = .none
            }

            // KVO for item.status
            itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { _, _ in
                Task { @MainActor in
                switch item.status {
                case .unknown:
                    self.logItemDiagnostics(item, prefix: "[Player] Item status: unknown")
                    if self.isVideo || self.player == nil {
                        self.showLoading()
                    }
                case .readyToPlay:
                    self.logItemDiagnostics(item, prefix: "[Player] Item status: readyToPlay")
                    self.logAssetKeyStatus(asset, mediaURL: mediaURL)
                    let duration = item.duration.seconds
                    if duration.isFinite, duration > 0 {
                        self.audioState.durationSeconds = duration
                        if !self.audioState.isScrubbing {
                            self.audioState.scrubPositionSeconds = min(self.audioState.currentTimeSeconds, duration)
                        }
                    }
                    if !self.isVideo, !self.hasAutoPlayed {
                        logWithTimestamp("[Audio] Item ready; attempting autoplay")
                        newPlayer.play()
                        self.hasAutoPlayed = true
                    }
                    if self.isVideo {
                        self.showLoading("Starting media…")
                    } else {
                        self.overlayState = .none
                    }
                case .failed:
                    let err = item.error?.localizedDescription ?? "unknown"
                    self.logItemDiagnostics(item, prefix: "[Player] Item status: failed: \(err)")
                    self.logAssetKeyStatus(asset, mediaURL: mediaURL)
                    let nsErr = item.error as NSError?
                    logWithTimestamp("[Player] Item NSError domain=\(nsErr?.domain ?? "<nil>") code=\(nsErr?.code ?? 0) userInfo=\(nsErr?.userInfo ?? [:])")
                    // Check if the underlying cause is our loader's range-request error
                    let loaderDomain = "GigHiveMediaResourceLoader"
                    let underlying = nsErr?.userInfo[NSUnderlyingErrorKey] as? NSError
                    if let loaderMsg = self.loaderRef?.lastFailureMessage {
                        self.showFailure(loaderMsg, title: loaderMsg)
                    } else if underlying?.domain == loaderDomain,
                       let loaderMsg = underlying?.localizedDescription {
                        self.showFailure(loaderMsg, title: loaderMsg)
                    } else if nsErr?.domain == loaderDomain {
                        self.showFailure(err, title: err)
                    } else {
                        self.showFailure(err)
                    }
                @unknown default:
                    logWithTimestamp("[Player] Item status: unknown default")
                }
                }
            }

            likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { _, change in
                let newValue = change.newValue ?? false
                self.logItemDiagnostics(item, prefix: "[PlayerItem] isPlaybackLikelyToKeepUp=\(newValue)")
            }

            bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { _, change in
                let newValue = change.newValue ?? false
                self.logItemDiagnostics(item, prefix: "[PlayerItem] isPlaybackBufferEmpty=\(newValue)")
            }

            bufferFullObserver = item.observe(\.isPlaybackBufferFull, options: [.initial, .new]) { _, change in
                let newValue = change.newValue ?? false
                self.logItemDiagnostics(item, prefix: "[PlayerItem] isPlaybackBufferFull=\(newValue)")
            }

            // Observe timeControlStatus to know when playback starts/waits
            timeControlObserver = newPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
                let currentTime = player.currentTime().seconds
                let rate = player.rate
                Task { @MainActor in
                switch player.timeControlStatus {
                case .paused:
                    logWithTimestamp("[Player] ⏸️ timeControlStatus=paused rate=\(rate) time=\(currentTime)")
                    self.audioState.isPlaying = false
                    if self.errorMessage == nil, currentTime <= 0.1, (self.isVideo || self.player == nil) {
                        self.showLoading()
                    }
                case .waitingToPlayAtSpecifiedRate:
                    let reason = player.reasonForWaitingToPlay?.rawValue ?? "<nil>"
                    logWithTimestamp("[Player] ⏳ timeControlStatus=waiting (reason=\(reason)) rate=\(rate) time=\(currentTime)")
                    self.audioState.isPlaying = false
                    self.logItemDiagnostics(item, prefix: "[Player] Waiting diagnostics")
                    if self.isVideo {
                        self.showLoading("Buffering video...")
                    }
                case .playing:
                    logWithTimestamp("[Player] ▶️ timeControlStatus=playing rate=\(rate) time=\(currentTime)")
                    self.audioState.isPlaying = true
                    if !self.hasAutoPlayed {
                        self.hasAutoPlayed = true
                    }
                    self.overlayState = .none
                @unknown default:
                    logWithTimestamp("[Player] ❓ timeControlStatus=unknown rate=\(rate) time=\(currentTime)")
                }
                }
            }
            
            // Observe rate changes directly
            rateObserver = newPlayer.observe(\.rate, options: [.old, .new]) { player, change in
                let oldRate = change.oldValue ?? 0.0
                let newRate = change.newValue ?? 0.0
                let currentTime = player.currentTime().seconds
                logWithTimestamp("[Player] 🎚️ Rate changed: \(oldRate) -> \(newRate) at time=\(currentTime)")
            }

            timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { time in
                let seconds = time.seconds
                Task { @MainActor in
                    if seconds.isFinite {
                        self.audioState.currentTimeSeconds = seconds
                        if !self.audioState.isScrubbing {
                            self.audioState.scrubPositionSeconds = seconds
                        }
                        if !self.isVideo, seconds > 0 {
                            self.overlayState = .none
                        }
                    }
                    let duration = item.duration.seconds
                    if duration.isFinite, duration > 0 {
                        self.audioState.durationSeconds = duration
                    }
                }
            }

            // Add a short timeout to report if playback does not become ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.errorMessage == nil, item.status != .readyToPlay {
                    self.logItemDiagnostics(item, prefix: "[Player] Still not ready after 3s")
                    self.showLoading("Loading media…")
                }
            }
    }

    private func logItemDiagnostics(_ item: AVPlayerItem, prefix: String) {
        let durationSeconds = item.duration.seconds
        let durationDescription = durationSeconds.isFinite ? String(format: "%.3f", durationSeconds) : "non-finite"
        let loadedRanges = item.loadedTimeRanges.compactMap { value -> String? in
            let range = value.timeRangeValue
            let start = CMTimeGetSeconds(range.start)
            let duration = CMTimeGetSeconds(range.duration)
            guard start.isFinite, duration.isFinite else { return nil }
            return String(format: "[start=%.3f,duration=%.3f,end=%.3f]", start, duration, start + duration)
        }
        let errorText = item.error?.localizedDescription ?? "<nil>"
        logWithTimestamp("\(prefix) status=\(item.status.rawValue) keepUp=\(item.isPlaybackLikelyToKeepUp) bufferEmpty=\(item.isPlaybackBufferEmpty) bufferFull=\(item.isPlaybackBufferFull) duration=\(durationDescription) loadedTimeRanges=\(loadedRanges) error=\(errorText)")
        if let errorLog = item.errorLog()?.events.last {
            let details: [String: Any] = [
                "uri": errorLog.uri ?? "<nil>",
                "statusCode": errorLog.errorStatusCode,
                "domain": errorLog.errorDomain,
                "comment": errorLog.errorComment ?? "<nil>",
                "serverAddress": errorLog.serverAddress ?? "<nil>"
            ]
            logWithTimestamp("[Player] ErrorLog: \(details)")
        }
    }

    /// Non-destructive asset key status check.  Only reads cached status via
    /// statusOfValue(forKey:) — never calls loadValuesAsynchronously, so it
    /// cannot poison keys that AVPlayerItem has not attempted to load yet.
    private func logAssetKeyStatus(_ asset: AVURLAsset, mediaURL: URL) {
        let keys = ["playable", "duration", "tracks", "hasProtectedContent"]
        var results: [String] = []
        for key in keys {
            var error: NSError?
            let status = asset.statusOfValue(forKey: key, error: &error)
            let errorText = error?.localizedDescription ?? "<nil>"
            results.append("\(key)=\(assetKeyStatusDescription(status)) error=\(errorText)")
        }
        let durationSeconds = asset.duration.seconds
        let durationDescription = durationSeconds.isFinite ? String(format: "%.3f", durationSeconds) : "non-finite"
        logWithTimestamp("[Asset] url=\(mediaURL.absoluteString) duration=\(durationDescription) keyStatuses=\(results)")
    }

    private func assetKeyStatusDescription(_ status: AVKeyValueStatus) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .loading:
            return "loading"
        case .loaded:
            return "loaded"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
        @unknown default:
            return "unknown-default"
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
