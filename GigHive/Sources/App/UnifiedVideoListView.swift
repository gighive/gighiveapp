import SwiftUI

// MARK: - Alert enum (file-private)

private enum UnifiedListAlert {
    case reportConfirm(UnifiedVideo)
    case reportFeedback(String)
    case retractConfirm(UnifiedVideo)
    case retractFeedback(String)
    case deleteConfirm(UnifiedVideo)
    case deleteFeedback(String)
    case error(String)
}

// MARK: - UnifiedVideoListView

/// Unified card-layout list view for both guest and authenticated media contexts.
/// Context-driven: VideoListContext + VideoListCapabilities determine which features are active.
///
/// Phase 2: guest path fully wired (polling, pill, flag, delete).
/// Phase 3: authenticated search + UserDefaults viewed-state verified.
struct UnifiedVideoListView: View {
    let context: VideoListContext

    // MARK: Common state

    @State private var videos: [UnifiedVideo] = []
    @State private var hasLoadedOnce = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeAlert: UnifiedListAlert?
    @State private var viewedIds: Set<Int> = []
    @State private var ownUploadIds: Set<Int> = []
    @State private var reportedIds: Set<Int> = []
    @State private var deletedIds: Set<Int> = []

    // MARK: Authenticated delete state (Phase 5)

    /// Tracks in-flight authenticated deletes to prevent double-tap sending two API calls.
    @State private var isDeletingIds: Set<Int> = []

    // MARK: Guest-only state

    /// "active", "expired", or nil if not yet loaded (guest path only)
    @State private var galleryStatus: String?
    @State private var daysRemaining: Int?
    /// Server-reported total video count (may differ from mapped count if some URLs fail)
    @State private var serverVideoCount: Int = 0

    // MARK: Live-polling state (guest only, canLivePoll)

    @Environment(\.scenePhase) private var scenePhase
    @State private var previousVideoCount: Int = 0
    @State private var showNewVideosPill = false
    @State private var newVideosPillCount = 0
    @State private var isSilentPolling = false
    @State private var pillDismissTask: Task<Void, Never>?

    // MARK: Search state (authenticated only, canSearch)

    @State private var searchText = ""

    // MARK: Constants

    private static let galleryPollInterval: Double = 30
    private static let pillAutoDismissNanoseconds: UInt64 = 8_000_000_000

    private let galleryTimer = Timer.publish(
        every: Self.galleryPollInterval, on: .main, in: .common
    ).autoconnect()

    // MARK: Computed helpers

    private var capabilities: VideoListCapabilities { context.capabilities }

    private var alertBinding: Binding<Bool> {
        Binding(get: { activeAlert != nil }, set: { if !$0 { activeAlert = nil } })
    }

    private var navigationTitle: String {
        switch context {
        case .guest(let record): return record.eventName
        case .authenticated: return "Media Database"
        }
    }

    /// Videos after applying the deletedIds client-side filter and optional search filter.
    private var filteredVideos: [UnifiedVideo] {
        let visible = videos.filter { !deletedIds.contains($0.id) }
        guard capabilities.canSearch && !searchText.isEmpty else { return visible }
        let q = searchText.lowercased()
        return visible.filter {
            ($0.label?.lowercased().contains(q) == true) ||
            ($0.displayName?.lowercased().contains(q) == true) ||
            ($0.orgName?.lowercased().contains(q) == true) ||
            ($0.date?.lowercased().contains(q) == true)
        }
    }

    /// Credential to pass into UnifiedVideoPlayerConfig for this context.
    private var playerCredential: AuthCredential? {
        switch context {
        case .guest: return nil
        case .authenticated(_, let credential, _): return credential
        }
    }

    /// TLS setting to pass into UnifiedVideoPlayerConfig for this context.
    private var playerAllowInsecureTLS: Bool {
        switch context {
        case .guest: return false
        case .authenticated(_, _, let allowInsecureTLS): return allowInsecureTLS
        }
    }

    // MARK: - Pill view

    private var pillView: some View {
        HStack(spacing: 8) {
            Text("↑ \(newVideosPillCount) new video\(newVideosPillCount == 1 ? "" : "s") added")
                .bold()
                .font(.caption)
                .foregroundColor(.white)
            Spacer()
            Button(action: {
                pillDismissTask?.cancel()
                pillDismissTask = nil
                withAnimation { showNewVideosPill = false }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange)
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("unified_list_new_pill")
    }

    // MARK: - Body

    var body: some View {
        mainScrollView
            .dismissKeyboardOnScroll()
            .ghFullScreenBackground(GHTheme.bg)
            .overlay(
                Group {
                    if showNewVideosPill {
                        VStack { pillView; Spacer() }
                    }
                },
                alignment: .top
            )
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if case .guest(let record) = context {
                    previousVideoCount = record.lastSeenVideoCount
                }
                if case .authenticated = context {
                    loadViewedIdsFromDefaults()
                }
                Task { await loadVideos() }
            }
            .onReceive(galleryTimer) { _ in
                guard capabilities.canLivePoll, scenePhase == .active else { return }
                Task { await loadVideos(silent: true) }
            }
            .onChange(of: scenePhase) { phase in
                guard capabilities.canLivePoll, phase == .active else { return }
                Task { await loadVideos(silent: true) }
            }
            .onDisappear {
                pillDismissTask?.cancel()
                pillDismissTask = nil
                if case .authenticated = context {
                    saveViewedIdsToDefaults()
                }
            }
            .alert(isPresented: alertBinding) { makeAlert() }
    }

    // MARK: - Scroll view (iOS version + capability dispatch)

    /// Adds pull-to-refresh and .searchable for authenticated path on iOS 15+.
    /// Guest path always uses a plain ScrollView (live-poll timer drives refreshes).
    @ViewBuilder
    private var mainScrollView: some View {
        if #available(iOS 15, *), !capabilities.canLivePoll {
            // Authenticated on iOS 15+: pull-to-refresh + searchable
            ScrollView {
                contentVStack
            }
            .refreshable {
                await loadVideos()
            }
            .searchable(text: $searchText, placement: .automatic)
        } else {
            // Guest (any iOS) or authenticated on iOS 14: plain ScrollView.
            // Authenticated iOS 14 shows an inline search bar inside contentVStack.
            ScrollView {
                contentVStack
            }
        }
    }

    // MARK: - Content VStack

    @ViewBuilder
    private var contentVStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            // iOS 14 fallback search bar — only when canSearch and .searchable is not available
            if capabilities.canSearch {
                if #unavailable(iOS 15) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(GHTheme.muted)
                        TextField("Search by band, song, or date", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(.vertical, 6)
                    }
                    .padding(.horizontal, 10)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .accessibilityIdentifier("unified_list_search_field")
                }
            }

            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: GHTheme.accent))
                    Text("Loading…")
                        .font(.subheadline)
                        .ghForeground(GHTheme.muted)
                }
                .padding(.vertical, 8)

            } else if let error = errorMessage {
                GHCard(pad: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Could not load")
                            .font(.headline)
                            .ghForeground(GHTheme.text)
                        Text(error)
                            .font(.subheadline)
                            .ghForeground(GHTheme.muted)
                        Button("Try Again") { Task { await loadVideos() } }
                            .buttonStyle(GHButtonStyle(color: GHTheme.accent))
                    }
                }

            } else if galleryStatus == "expired" {
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

            } else if hasLoadedOnce && filteredVideos.isEmpty {
                emptyStateView

            } else if hasLoadedOnce {
                videoCountCaption
                ForEach(filteredVideos) { video in
                    videoCard(video: video)
                }
            }

            // Guest-only footer: warns user that gallery access is device-specific
            if case .guest = context {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Your gallery access is stored on this device. Deleting the app will remove access.")
                        .font(.caption2)
                        .ghForeground(GHTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Header view

    @ViewBuilder
    private var headerView: some View {
        switch context {
        case .guest(let record):
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
        case .authenticated:
            HStack(spacing: 8) {
                Image("beelogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: (UIFont.preferredFont(forTextStyle: .title2).pointSize + 2) * 2.66)
                Text("Media Database")
                    .font(.title3).bold()
                    .ghForeground(GHTheme.text)
            }
        }
    }

    // MARK: - Count caption

    @ViewBuilder
    private var videoCountCaption: some View {
        switch context {
        case .guest:
            if let days = daysRemaining {
                let count = serverVideoCount > 0 ? serverVideoCount : videos.count
                Text("Available for \(days) more days · \(count) video\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .ghForeground(GHTheme.muted)
            }
        case .authenticated(_, let credential, _):
            VStack(alignment: .leading, spacing: 2) {
                if let user = credential?.displayUser {
                    Text("Logged in as: \(user)")
                        .font(.caption)
                        .ghForeground(GHTheme.muted)
                }
                let count = filteredVideos.count
                Text("\(count) entr\(count == 1 ? "y" : "ies")")
                    .font(.caption)
                    .ghForeground(GHTheme.muted)
            }
        }
    }

    // MARK: - Empty state view

    @ViewBuilder
    private var emptyStateView: some View {
        GHCard(pad: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("No videos yet")
                    .font(.headline)
                    .ghForeground(GHTheme.text)
                Text(emptyStateMessage)
                    .font(.subheadline)
                    .ghForeground(GHTheme.muted)
                if case .guest = context, let days = daysRemaining {
                    Text("Gallery available for \(days) more days.")
                        .font(.caption)
                        .ghForeground(GHTheme.muted)
                }
            }
        }
    }

    private var emptyStateMessage: String {
        switch context {
        case .guest:
            return "Check back soon as the organizer reviews other submissions."
        case .authenticated:
            return searchText.isEmpty
                ? "No media in the database yet."
                : "No results match your search."
        }
    }

    // MARK: - Video card

    private func videoCard(video: UnifiedVideo) -> some View {
        GHCard(pad: 10) {
            HStack(alignment: .center, spacing: 12) {
                NavigationLink(destination: UnifiedVideoPlayerView(
                    config: UnifiedVideoPlayerConfig(
                        url: video.streamURL,
                        credential: playerCredential,
                        allowInsecureTLS: playerAllowInsecureTLS,
                        fileType: video.fileType
                    ),
                    onAppear: {
                        logWithTimestamp("[UnifiedList] Player appeared — marking viewed id=\(video.id)")
                        markViewed(video.id)
                    }
                )) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.yellow)
                            .frame(width: 40, height: 40)
                        AsyncThumbnail(url: video.thumbnailURL, credential: playerCredential)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(primaryLabel(for: video))
                                    .font(.subheadline)
                                    .ghForeground(GHTheme.text)
                                if capabilities.canShowNewBadge && !viewedIds.contains(video.id) {
                                    Text("New")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .cornerRadius(4)
                                        .accessibilityIdentifier("unified_list_new_badge")
                                }
                            }
                            Text(video.label?.isEmpty == false ? video.label! : "Untitled clip")
                                .font(.caption)
                                .ghForeground(GHTheme.muted)
                            let metaParts = [video.date, video.duration.map { trimmedDuration($0) }].compactMap { $0 }.filter { !$0.isEmpty }
                            if !metaParts.isEmpty {
                                Text(metaParts.joined(separator: "  ·  "))
                                    .font(.caption2)
                                    .ghForeground(GHTheme.muted)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("unified_list_video_cell")

                Spacer()

                if capabilities.canFlag {
                    Button {
                        if reportedIds.contains(video.id) {
                            activeAlert = .retractConfirm(video)
                        } else {
                            activeAlert = .reportConfirm(video)
                        }
                    } label: {
                        Image(systemName: reportedIds.contains(video.id) ? "flag.fill" : "flag")
                            .font(.title3)
                            .foregroundColor(.orange)
                    }
                    .accessibilityIdentifier("unified_list_flag_button")
                }

                if showDeleteButton(for: video) {
                    Button {
                        activeAlert = .deleteConfirm(video)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                    .accessibilityIdentifier("unified_list_delete_button")
                }
            }
        }
    }

    /// Primary display name for a card row (context-aware fallback).
    private func primaryLabel(for video: UnifiedVideo) -> String {
        // Guest: displayName is set from the API response; orgName is nil.
        // Authenticated: orgName is set from MediaEntry; displayName is nil (Phase 3 prereq).
        video.displayName ?? video.orgName ?? "Attendee"
    }

    private func showDeleteButton(for video: UnifiedVideo) -> Bool {
        switch capabilities.deleteScope {
        case .none:          return false
        case .uploaderOnly:  return ownUploadIds.contains(video.id)
        case .uploaderAndAdmin:
            // Admin: server-authoritative can_delete flag drives visibility (Phase 5 refactor).
            // Uploader: delete path deferred to JWT migration (Phase 3 Step 7); always hidden.
            guard case .authenticated(_, let credential, _) = context,
                  credential?.displayUser == "admin" else { return false }
            return video.canDelete
        }
    }

    // MARK: - Data loading

    @MainActor
    private func loadVideos(silent: Bool = false) async {
        switch context {
        case .guest(let record):
            guard let baseURL = URL(string: record.baseURLString) else {
                if !silent { errorMessage = "Invalid server URL." }
                return
            }
            await loadGuestVideos(record: record, baseURL: baseURL, silent: silent)
        case .authenticated(let baseURL, let credential, let allowInsecureTLS):
            await loadAuthenticatedVideos(
                baseURL: baseURL, credential: credential,
                allowInsecureTLS: allowInsecureTLS, silent: silent
            )
        }
    }

    @MainActor
    private func loadGuestVideos(record: GuestUploadRecord, baseURL: URL, silent: Bool) async {
        // Guard: don't overlap a silent poll with any active load
        if silent && (isLoading || isSilentPolling) { return }
        if !silent {
            isLoading = true
            errorMessage = nil
        } else {
            isSilentPolling = true
        }
        defer {
            if !silent { isLoading = false }
            else { isSilentPolling = false }
        }
        do {
            let resp = try await GuestGalleryAPIClient(baseURL: baseURL).fetchGallery(
                nonce: record.statusNonce
            )

            // Show pill when a background poll finds new videos
            if silent && resp.videos.count > previousVideoCount {
                let diff = resp.videos.count - previousVideoCount
                newVideosPillCount = diff
                pillDismissTask?.cancel()
                withAnimation { showNewVideosPill = true }
                pillDismissTask = Task {
                    try? await Task.sleep(nanoseconds: Self.pillAutoDismissNanoseconds)
                    guard !Task.isCancelled else { return }
                    withAnimation { showNewVideosPill = false }
                }
            }

            galleryStatus = resp.status
            daysRemaining = resp.daysRemaining
            serverVideoCount = resp.videoCount ?? resp.videos.count
            reportedIds = Set(resp.videos.filter { $0.reportedByMe }.map { $0.uploadJobId })
            previousVideoCount = resp.videos.count

            // Load viewed/own IDs from all records sharing this event so that whichever
            // nonce deduplication picks up next session has the full history.
            var allRecords = GuestUploadRecord.load()
            let eventRecords = allRecords.filter {
                $0.baseURLString == record.baseURLString && $0.eventName == record.eventName
            }
            viewedIds = Set(eventRecords.flatMap { $0.viewedUploadJobIds })
            ownUploadIds = Set(eventRecords.map { $0.uploadJobId })

            // Map GuestGalleryVideo → UnifiedVideo; skip entries with unresolvable URLs
            let mapped: [UnifiedVideo] = resp.videos.compactMap { video in
                guard let streamURL = buildGuestStreamURL(video: video, baseURL: baseURL) else {
                    logWithTimestamp("[UnifiedList] guest: skipping id=\(video.uploadJobId) — could not resolve streamURL from \(video.streamUrl)")
                    return nil
                }
                return UnifiedVideo(
                    id: video.uploadJobId,
                    displayName: video.displayName,
                    orgName: nil,
                    label: video.label,
                    streamURL: streamURL,
                    thumbnailURL: buildGuestThumbnailURL(video: video, baseURL: baseURL),
                    fileType: .video,
                    isOwnUpload: ownUploadIds.contains(video.uploadJobId),
                    canDelete: false,       // guest delete uses nonce-based authorization, not can_delete
                    isReported: reportedIds.contains(video.uploadJobId),
                    date: nil,
                    duration: nil
                )
            }
            withAnimation(.default) { videos = mapped }
            hasLoadedOnce = true

            let vc = serverVideoCount
            if silent {
                logWithTimestamp("[UnifiedList] guest poll silent: videoCount=\(vc)")
            } else {
                logWithTimestamp("[UnifiedList] guest load: ownUploadIds=\(ownUploadIds.sorted()) viewedIds=\(viewedIds.sorted()) videoCount=\(vc)")
            }

            // Update lastSeenVideoCount for every record sharing this event
            var needsSave = false
            for i in allRecords.indices
                where allRecords[i].baseURLString == record.baseURLString
                   && allRecords[i].eventName == record.eventName
                   && allRecords[i].lastSeenVideoCount != vc {
                allRecords[i].lastSeenVideoCount = vc
                needsSave = true
            }
            if needsSave { GuestUploadRecord.save(allRecords) }

        } catch GuestGalleryError.accessDenied {
            if !silent { errorMessage = "Gallery access could not be verified. The nonce may be invalid." }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func loadAuthenticatedVideos(
        baseURL: URL, credential: AuthCredential?,
        allowInsecureTLS: Bool, silent: Bool
    ) async {
        // Authenticated list does not use silent polling; pull-to-refresh drives refreshes
        guard !silent else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let client = DatabaseAPIClient(
                baseURL: baseURL, credential: credential, allowInsecure: allowInsecureTLS
            )
            let entries = try await client.fetchMediaList()
            let mapped: [UnifiedVideo] = entries.compactMap { entry in
                guard let streamURL = URL(string: entry.url, relativeTo: baseURL)?.absoluteURL else {
                    logWithTimestamp("[UnifiedList] auth: skipping id=\(entry.id) — could not resolve streamURL from url=\(entry.url)")
                    return nil
                }
                let fileType = MediaFileType(rawValue: entry.fileType) ?? .video
                if MediaFileType(rawValue: entry.fileType) == nil {
                    logWithTimestamp("[UnifiedList] auth: unknown fileType='\(entry.fileType)' for id=\(entry.id), defaulting to .video")
                }
                return UnifiedVideo(
                    id: entry.id,
                    displayName: nil,       // Phase 3 server prereq: database.php response field
                    orgName: entry.orgName,
                    label: entry.songTitle,
                    streamURL: streamURL,
                    thumbnailURL: buildAuthThumbnailURL(entry: entry, baseURL: baseURL),
                    fileType: fileType,
                    isOwnUpload: entry.canDelete,   // proxy for ownership until JWT migration
                    canDelete: entry.canDelete,
                    isReported: false,      // Flag/report not supported for authenticated context
                    date: entry.date,
                    duration: entry.duration
                )
            }
            videos = mapped
            hasLoadedOnce = true
            logWithTimestamp("[UnifiedList] auth load: entries=\(entries.count) mapped=\(mapped.count) canDelete=\(mapped.filter { $0.canDelete }.count)")
        } catch {
            errorMessage = error.localizedDescription
            logWithTimestamp("[UnifiedList] auth load error: \(error.localizedDescription)")
        }
    }

    // MARK: - URL helpers

    private func buildGuestStreamURL(video: GuestGalleryVideo, baseURL: URL) -> URL? {
        URL(string: video.streamUrl, relativeTo: baseURL)?.absoluteURL
    }

    private func buildGuestThumbnailURL(video: GuestGalleryVideo, baseURL: URL) -> URL? {
        guard let thumbStr = video.thumbnailUrl else { return nil }
        return URL(string: thumbStr, relativeTo: baseURL)?.absoluteURL
    }

    private func buildAuthThumbnailURL(entry: MediaEntry, baseURL: URL) -> URL? {
        guard let thumbStr = entry.thumbnailUrl, !thumbStr.isEmpty else { return nil }
        return URL(string: thumbStr, relativeTo: baseURL)?.absoluteURL
    }

    /// Converts server-format "HH:MM:SS" to a compact display string.
    /// Drops the hours component when zero: "00:06:00" → "6:00", "01:06:00" → "1:06:00".
    private func trimmedDuration(_ hms: String) -> String {
        let parts = hms.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let h = Int(parts[0]), let m = Int(parts[1]) else { return hms }
        return h == 0 ? "\(m):\(parts[2])" : "\(h):\(parts[1]):\(parts[2])"
    }

    // MARK: - Viewed state

    private func markViewed(_ id: Int) {
        guard !viewedIds.contains(id) else { return }
        viewedIds.insert(id)
        switch context {
        case .guest(let record):
            updateAllGuestEventRecords(record: record) { r in
                guard !r.viewedUploadJobIds.contains(id) else { return false }
                r.viewedUploadJobIds.append(id)
                return true
            }
        case .authenticated:
            // Persisted to UserDefaults in onDisappear via saveViewedIdsToDefaults()
            break
        }
    }

    /// Applies `modify` to every GuestUploadRecord sharing the same event (baseURLString + eventName)
    /// and saves if any changed. Mirrors GuestGalleryView.updateAllEventRecords.
    private func updateAllGuestEventRecords(
        record: GuestUploadRecord, modify: (inout GuestUploadRecord) -> Bool
    ) {
        var all = GuestUploadRecord.load()
        var dirty = false
        for i in all.indices
            where all[i].baseURLString == record.baseURLString
               && all[i].eventName == record.eventName {
            if modify(&all[i]) { dirty = true }
        }
        if dirty { GuestUploadRecord.save(all) }
    }

    private func loadViewedIdsFromDefaults() {
        guard case .authenticated(let baseURL, _, _) = context else { return }
        let key = viewedIdsDefaultsKey(baseURL: baseURL)
        if let saved = UserDefaults.standard.array(forKey: key) as? [Int] {
            viewedIds = Set(saved)
        }
    }

    private func saveViewedIdsToDefaults() {
        guard case .authenticated(let baseURL, _, _) = context else { return }
        let key = viewedIdsDefaultsKey(baseURL: baseURL)
        UserDefaults.standard.set(Array(viewedIds), forKey: key)
    }

    private func viewedIdsDefaultsKey(baseURL: URL) -> String {
        "gh_viewed_ids_\(baseURL.host ?? baseURL.absoluteString)"
    }

    // MARK: - Guest API actions

    @MainActor
    private func submitReport(video: UnifiedVideo) async {
        guard case .guest(let record) = context,
              let baseURL = URL(string: record.baseURLString) else { return }
        do {
            let serverReported = try await GuestGalleryAPIClient(baseURL: baseURL).setVideoReported(
                nonce: record.statusNonce,
                uploadJobId: video.id,
                reported: true
            )
            if serverReported { reportedIds.insert(video.id) } else { reportedIds.remove(video.id) }
            activeAlert = .reportFeedback("Thank you. The event organizer will review your report.")
        } catch {
            activeAlert = .error(error.localizedDescription)
        }
    }

    @MainActor
    private func submitRetract(video: UnifiedVideo) async {
        guard case .guest(let record) = context,
              let baseURL = URL(string: record.baseURLString) else { return }
        do {
            let serverReported = try await GuestGalleryAPIClient(baseURL: baseURL).setVideoReported(
                nonce: record.statusNonce,
                uploadJobId: video.id,
                reported: false
            )
            if serverReported { reportedIds.insert(video.id) } else { reportedIds.remove(video.id) }
            activeAlert = .retractFeedback("Your report has been removed.")
        } catch {
            activeAlert = .error(error.localizedDescription)
        }
    }

    @MainActor
    private func performDelete(video: UnifiedVideo) async {
        switch context {
        case .guest(let record):
            guard let baseURL = URL(string: record.baseURLString) else { return }
            // Each upload was submitted with its own nonce; the delete API validates that the
            // nonce matches the uploader, so look up the correct record for this video.
            let allRecords = GuestUploadRecord.load()
            let uploaderNonce = allRecords.first {
                $0.baseURLString == record.baseURLString &&
                $0.eventName == record.eventName &&
                $0.uploadJobId == video.id
            }?.statusNonce ?? record.statusNonce
            do {
                try await GuestGalleryAPIClient(baseURL: baseURL).deleteVideo(
                    nonce: uploaderNonce,
                    uploadJobId: video.id
                )
                deletedIds.insert(video.id)
                activeAlert = .deleteFeedback("Your video has been removed from the gallery.")
            } catch {
                activeAlert = .error(error.localizedDescription)
            }
        case .authenticated(let baseURL, let credential, let allowInsecureTLS):
            // Only admin can reach this point — showDeleteButton returns false for uploader.
            // Uploader delete via JWT role-claim is deferred to Phase 3 Step 7 (JWT migration).
            guard credential?.displayUser == "admin" else {
                logWithTimestamp("[UnifiedList] deleteAuthenticated: uploader delete not yet implemented (Phase 3 Step 7 deferred)")
                activeAlert = .error("Delete is not yet available for this account type.")
                return
            }
            // Prevent double-tap: ignore if a delete is already in flight for this video.
            guard isDeletingIds.insert(video.id).inserted else { return }
            defer { isDeletingIds.remove(video.id) }

            let host = baseURL.host ?? baseURL.absoluteString
            logWithTimestamp("[UnifiedList] deleteAuthenticated start file_id=\(video.id) host=\(host)")
            do {
                let client = DatabaseAPIClient(
                    baseURL: baseURL, credential: credential, allowInsecure: allowInsecureTLS
                )
                // Admin path: sends {"asset_ids": [id]} — server does not require a delete token.
                let resp = try await client.deleteMediaFileAsAdmin(fileId: video.id)
                logWithTimestamp("[UnifiedList] deleteAuthenticated response deleted=\(resp.deletedCount) errors=\(resp.errorCount)")
                if resp.deletedCount == 1 {
                    deletedIds.insert(video.id)
                    activeAlert = .deleteFeedback("Your video has been removed from the database.")
                } else {
                    activeAlert = .error("Server did not delete the file (deleted=\(resp.deletedCount), errors=\(resp.errorCount)).")
                }
            } catch DatabaseError.httpError(403) {
                logWithTimestamp("[UnifiedList] deleteAuthenticated 403 file_id=\(video.id)")
                activeAlert = .error("You are not authorised to delete this video.")
            } catch {
                logWithTimestamp("[UnifiedList] deleteAuthenticated error: \(error)")
                activeAlert = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Alert construction

    private func makeAlert() -> Alert {
        switch activeAlert {
        case .reportConfirm(let video):  return makeReportConfirmAlert(video: video)
        case .reportFeedback(let msg):   return makeInfoAlert(title: "Report submitted", message: msg)
        case .retractConfirm(let video): return makeRetractConfirmAlert(video: video)
        case .retractFeedback(let msg):  return makeInfoAlert(title: "Report removed", message: msg)
        case .deleteConfirm(let video):  return makeDeleteConfirmAlert(video: video)
        case .deleteFeedback(let msg):   return makeInfoAlert(title: "Video removed", message: msg)
        case .error(let msg):            return makeInfoAlert(title: "Error", message: msg)
        case nil:                        return Alert(title: Text(""))
        }
    }

    private func makeReportConfirmAlert(video: UnifiedVideo) -> Alert {
        Alert(
            title: Text("Report this video?"),
            message: Text("Flag this video for organizer review."),
            primaryButton: .destructive(Text("Report")) {
                Task { await submitReport(video: video) }
            },
            secondaryButton: .cancel()
        )
    }

    private func makeRetractConfirmAlert(video: UnifiedVideo) -> Alert {
        Alert(
            title: Text("Remove your report?"),
            message: Text("This will retract your flag on this video."),
            primaryButton: .default(Text("Remove")) {
                Task { await submitRetract(video: video) }
            },
            secondaryButton: .cancel()
        )
    }

    private func makeDeleteConfirmAlert(video: UnifiedVideo) -> Alert {
        Alert(
            title: Text("Delete your video?"),
            message: Text("This removes your clip from the gallery. You'll still have access to view other videos."),
            primaryButton: .destructive(Text("Delete")) {
                Task { await performDelete(video: video) }
            },
            secondaryButton: .cancel()
        )
    }

    private func makeInfoAlert(title: String, message: String) -> Alert {
        Alert(
            title: Text(title),
            message: Text(message),
            dismissButton: .default(Text("OK"))
        )
    }
}

// MARK: - Preview

struct UnifiedVideoListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            UnifiedVideoListView(context: .guest(record: GuestUploadRecord(
                statusNonce: "preview",
                uploadJobId: 1,
                eventName: "StormPigs — 2026-07-17",
                submittedAt: Date(),
                baseURLString: "https://dev.gighive.app",
                approvalStatus: "approved",
                lastSeenVideoCount: 0,
                viewedUploadJobIds: [],
                daysRemaining: 87
            )))
        }
    }
}
