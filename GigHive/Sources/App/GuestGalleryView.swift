import SwiftUI
import AVKit

private enum GalleryAlert {
    case reportConfirm(GuestGalleryVideo)
    case reportFeedback(String)
    case deleteConfirm(GuestGalleryVideo)
    case deleteFeedback(String)
    case error(String)
}

struct GuestGalleryView: View {
    let record: GuestUploadRecord

    @State private var isLoading = false
    @State private var galleryResponse: GuestGalleryResponse?
    @State private var errorMessage: String?
    @State private var activeAlert: GalleryAlert?
    @State private var viewedIds: Set<Int> = []
    @State private var reportedIds: Set<Int> = []
    @State private var deletedIds: Set<Int> = []

    private var alertBinding: Binding<Bool> {
        Binding(get: { activeAlert != nil }, set: { if !$0 { activeAlert = nil } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                HStack(spacing: 8) {
                    Image("beelogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: (UIFont.preferredFont(forTextStyle: .title2).pointSize + 2) * 2.66)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Event Gallery")
                            .font(.title3).bold()
                            .ghForeground(GHTheme.text)
                        Text(record.eventName)
                            .font(.caption)
                            .ghForeground(GHTheme.muted)
                    }
                }

                if isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: GHTheme.accent))
                        Text("Loading gallery…")
                            .font(.subheadline)
                            .ghForeground(GHTheme.muted)
                    }
                    .padding(.vertical, 8)

                } else if let error = errorMessage {
                    GHCard(pad: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Could not load gallery")
                                .font(.headline)
                                .ghForeground(GHTheme.text)
                            Text(error)
                                .font(.subheadline)
                                .ghForeground(GHTheme.muted)
                            Button("Try Again") { Task { await loadGallery() } }
                                .buttonStyle(GHButtonStyle(color: GHTheme.accent))
                        }
                    }

                } else if let resp = galleryResponse {
                    if resp.status == "expired" {
                        GHCard(pad: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Gallery expired")
                                    .font(.headline)
                                    .ghForeground(GHTheme.text)
                                Text("This event gallery is no longer available.")
                                    .font(.subheadline)
                                    .ghForeground(GHTheme.muted)
                            }
                        }
                    } else if resp.videos.isEmpty {
                        GHCard(pad: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No videos yet")
                                    .font(.headline)
                                    .ghForeground(GHTheme.text)
                                Text("Check back soon as the organizer reviews other submissions.")
                                    .font(.subheadline)
                                    .ghForeground(GHTheme.muted)
                                if let days = resp.daysRemaining {
                                    Text("Gallery available for \(days) more days.")
                                        .font(.caption)
                                        .ghForeground(GHTheme.muted)
                                }
                            }
                        }
                    } else {
                        let videoCount = resp.videos.count
                        if let days = resp.daysRemaining {
                            Text("Available for \(days) more days · \(videoCount) video\(videoCount == 1 ? "" : "s")")
                                .font(.caption)
                                .ghForeground(GHTheme.muted)
                        }
                        ForEach(resp.videos.filter { !deletedIds.contains($0.uploadJobId) }) { video in
                            GHCard(pad: 10) {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(video.displayName ?? "Attendee")
                                                .font(.subheadline)
                                                .ghForeground(GHTheme.text)
                                            if !viewedIds.contains(video.uploadJobId) {
                                                Text("New")
                                                    .font(.caption2)
                                                    .foregroundColor(.orange)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.orange.opacity(0.15))
                                                    .cornerRadius(4)
                                            }
                                        }
                                        if let label = video.label, !label.isEmpty {
                                            Text(label)
                                                .font(.caption)
                                                .ghForeground(GHTheme.muted)
                                        }
                                    }
                                    Spacer()
                                    if let streamURL = buildStreamURL(video: video) {
                                        NavigationLink(destination: VideoPlayerView(url: streamURL)) {
                                            Image(systemName: "play.circle.fill")
                                                .font(.title2)
                                                .ghForeground(GHTheme.accent)
                                        }
                                        .simultaneousGesture(TapGesture().onEnded {
                                            logWithTimestamp("[Gallery] Play tapped — url=\(streamURL.absoluteString)")
                                            markViewed(video.uploadJobId)
                                        })
                                    }
                                    Button {
                                        activeAlert = .reportConfirm(video)
                                    } label: {
                                        Image(systemName: reportedIds.contains(video.uploadJobId) ? "flag.fill" : "flag")
                                            .font(.title3)
                                            .foregroundColor(.orange)
                                    }
                                    if video.uploadJobId == record.uploadJobId {
                                        Button {
                                            activeAlert = .deleteConfirm(video)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.title3)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("Your gallery access is stored on this device. Deleting the app will remove access.")
                    .font(.caption2)
                    .ghForeground(GHTheme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ghFullScreenBackground(GHTheme.bg)
        .navigationTitle(record.eventName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await loadGallery() }
        }
        .alert(isPresented: alertBinding) {
            makeAlert()
        }
    }

    private func buildStreamURL(video: GuestGalleryVideo) -> URL? {
        guard let base = URL(string: record.baseURLString) else { return nil }
        let url = URL(string: video.streamUrl, relativeTo: base)?.absoluteURL
        logWithTimestamp("[Gallery] buildStreamURL: raw=\(video.streamUrl) base=\(record.baseURLString) final=\(url?.absoluteString ?? "nil")")
        return url
    }

    @MainActor
    private func loadGallery() async {
        guard let baseURL = URL(string: record.baseURLString) else {
            errorMessage = "Invalid server URL."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp = try await GuestGalleryAPIClient(baseURL: baseURL).fetchGallery(nonce: record.statusNonce)
            galleryResponse = resp
            let vc = resp.videoCount ?? resp.videos.count
            let fresh = GuestUploadRecord.load().first { $0.statusNonce == record.statusNonce } ?? record
            viewedIds = Set(fresh.viewedUploadJobIds)
            if vc != fresh.lastSeenVideoCount {
                var updated = fresh
                updated.lastSeenVideoCount = vc
                GuestUploadRecord.upsert(updated)
            }
        } catch GuestGalleryError.accessDenied {
            errorMessage = "Gallery access could not be verified. The nonce may be invalid."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markViewed(_ uploadJobId: Int) {
        guard !viewedIds.contains(uploadJobId) else { return }
        viewedIds.insert(uploadJobId)
        let fresh = GuestUploadRecord.load().first { $0.statusNonce == record.statusNonce } ?? record
        var updated = fresh
        updated.viewedUploadJobIds = Array(viewedIds)
        GuestUploadRecord.upsert(updated)
    }

    @MainActor
    private func submitReport(video: GuestGalleryVideo) async {
        guard let baseURL = URL(string: record.baseURLString) else { return }
        do {
            try await GuestGalleryAPIClient(baseURL: baseURL).reportVideo(
                nonce: record.statusNonce,
                uploadJobId: video.uploadJobId
            )
            reportedIds.insert(video.uploadJobId)
            activeAlert = .reportFeedback("Thank you. The event organizer will review your report.")
        } catch {
            activeAlert = .error(error.localizedDescription)
        }
    }

    @MainActor
    private func performDelete(video: GuestGalleryVideo) async {
        guard let baseURL = URL(string: record.baseURLString) else { return }
        do {
            try await GuestGalleryAPIClient(baseURL: baseURL).deleteVideo(
                nonce: record.statusNonce,
                uploadJobId: video.uploadJobId
            )
            deletedIds.insert(video.uploadJobId)
            activeAlert = .deleteFeedback("Your video has been removed from the gallery.")
        } catch {
            activeAlert = .error(error.localizedDescription)
        }
    }

    private func makeAlert() -> Alert {
        switch activeAlert {
        case .reportConfirm(let video):
            return Alert(
                title: Text("Report this video?"),
                message: Text("Flag this video for organizer review."),
                primaryButton: .destructive(Text("Report")) {
                    Task { await submitReport(video: video) }
                },
                secondaryButton: .cancel()
            )
        case .reportFeedback(let msg):
            return Alert(
                title: Text("Report submitted"),
                message: Text(msg),
                dismissButton: .default(Text("OK"))
            )
        case .deleteConfirm(let video):
            return Alert(
                title: Text("Delete your video?"),
                message: Text("This removes your clip from the gallery. You'll still have access to view other videos."),
                primaryButton: .destructive(Text("Delete")) {
                    Task { await performDelete(video: video) }
                },
                secondaryButton: .cancel()
            )
        case .deleteFeedback(let msg):
            return Alert(
                title: Text("Video removed"),
                message: Text(msg),
                dismissButton: .default(Text("OK"))
            )
        case .error(let msg):
            return Alert(
                title: Text("Error"),
                message: Text(msg),
                dismissButton: .default(Text("OK"))
            )
        case nil:
            return Alert(title: Text(""))
        }
    }
}

struct VideoPlayerView: View {
    let url: URL

    @State private var player: AVPlayer
    @State private var statusObserver: NSKeyValueObservation?
    @State private var timeControlObserver: NSKeyValueObservation?
    @State private var isBuffering: Bool = true

    init(url: URL) {
        self.url = url
        logWithTimestamp("[VideoPlayer] init url=\(url.absoluteString)")
        _player = State(wrappedValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            VideoPlayer(player: player)
                .edgesIgnoringSafeArea(.all)
            if isBuffering {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.4)
                    Text("Buffering...")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(20)
                .background(Color.black.opacity(0.55))
                .cornerRadius(12)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            let item = player.currentItem
            logWithTimestamp("[VideoPlayer] onAppear — status=\(item?.status.rawValue ?? -1) error=\(item?.error?.localizedDescription ?? "nil")")
            player.play()
            statusObserver = item?.observe(\.status, options: [.new, .initial]) { item, _ in
                switch item.status {
                case .readyToPlay:
                    logWithTimestamp("[VideoPlayer] AVPlayerItem status=readyToPlay")
                case .failed:
                    logWithTimestamp("[VideoPlayer] AVPlayerItem status=failed error=\(item.error?.localizedDescription ?? "nil") underlying=\((item.error as NSError?)?.userInfo[NSUnderlyingErrorKey] ?? "none")")
                case .unknown:
                    logWithTimestamp("[VideoPlayer] AVPlayerItem status=unknown")
                @unknown default:
                    break
                }
            }
            timeControlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { p, _ in
                Task { @MainActor in
                    switch p.timeControlStatus {
                    case .playing:
                        logWithTimestamp("[VideoPlayer] timeControlStatus=playing")
                        isBuffering = false
                    case .waitingToPlayAtSpecifiedRate:
                        logWithTimestamp("[VideoPlayer] timeControlStatus=waiting reason=\(p.reasonForWaitingToPlay?.rawValue ?? "<nil>")")
                        isBuffering = true
                    case .paused:
                        logWithTimestamp("[VideoPlayer] timeControlStatus=paused")
                        isBuffering = p.currentTime().seconds <= 0.1
                    @unknown default:
                        break
                    }
                }
            }
        }
        .onDisappear {
            player.pause()
            statusObserver = nil
            timeControlObserver = nil
        }
    }
}

struct GuestGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        GuestGalleryView(record: GuestUploadRecord(
            statusNonce: "preview",
            uploadJobId: 1,
            eventName: "StormPigs — 2026-07-17",
            submittedAt: Date(),
            baseURLString: "https://dev.gighive.app",
            approvalStatus: "approved",
            lastSeenVideoCount: 0,
            viewedUploadJobIds: [],
            daysRemaining: 87
        ))
    }
}
