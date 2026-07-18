import SwiftUI

struct SplashView: View {
    @EnvironmentObject var session: AuthSession
    @EnvironmentObject var guestSession: GuestUploadSession
    @State private var goToLogin = false
    @State private var goToDatabase = false
    @State private var goToUpload = false
    @State private var goToGuestUpload = false
    @State private var goToBannerGallery = false

    @State private var uploadRecords: [GuestUploadRecord] = []
    @State private var showApprovalBanner = false
    @State private var bannerRecord: GuestUploadRecord?
    @State private var newVideoNonces: Set<String> = []
    @State private var showRejectionAlert = false
    @State private var rejectedEventName: String?

    @Environment(\.scenePhase) private var scenePhase
    private static let splashPollInterval: Double = 60
    private let splashTimer = Timer.publish(every: Self.splashPollInterval, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {

            // Centered bee logo and app name
            GeometryReader { geometry in
                VStack(spacing: 16) {
                    Image("beelogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 0.66)
                    
                    Text("Gighive")
                        .font(.title3).bold()
                        .ghForeground(GHTheme.text)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 360)

            VStack(alignment: .leading, spacing: 4) {
                if let creds = session.credentials {
                    Text("User is logged into \(session.baseURL?.absoluteString ?? "<unknown>") as \(creds.user)")
                        .font(.footnote)
                        .foregroundColor(.orange)
                } else if uploadRecords.contains(where: { $0.approvalStatus == "approved" }) {
                    Text("Login for full database and upload access")
                        .font(.footnote)
                        .foregroundColor(.orange)
                } else {
                    Text("Please login first")
                        .font(.subheadline).bold()
                        .foregroundColor(.orange)
                    Text("You will be able to View the Database or Upload a File based on your credentials")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }

            Button("Login") {
                logWithTimestamp("[Splash] Login tapped")
                goToLogin = true
            }
            .buttonStyle(GHButtonStyle(color: .orange))

            if session.credentials != nil {
                NavigationLink(destination: DatabaseView()) {
                    Text("View the Database")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    logWithTimestamp("[Splash] View Database tapped (direct nav)")
                    session.intendedRoute = .viewDatabase
                })
                .buttonStyle(GHButtonStyle(color: .blue))
            } else {
                Button("View the Database") {
                    logWithTimestamp("[Splash] View Database tapped (login redirect)")
                    session.intendedRoute = .viewDatabase
                    goToLogin = true
                }
                .buttonStyle(GHButtonStyle(color: .blue))
            }

            Button("Upload a File") {
                logWithTimestamp("[Splash] Upload tapped")
                session.intendedRoute = .upload
                if session.credentials == nil { 
                    goToLogin = true 
                } else {
                    goToUpload = true
                    // Clear intended route once navigation is triggered to avoid bounce on back
                    session.intendedRoute = nil
                }
            }
            .buttonStyle(GHButtonStyle(color: .green))

            if guestSession.recentUploadSuccess {
                GHCard(pad: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Video submitted!")
                            .font(.subheadline).bold()
                            .ghForeground(GHTheme.text)
                        Text("Your video is in the moderation queue. The event organizer typically reviews submissions within 24–48 hours. Re-open the app after that time to check your status — if approved, a notification will appear on this screen.")
                            .font(.footnote)
                            .ghForeground(GHTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Got it") {
                            guestSession.recentUploadSuccess = false
                        }
                        .font(.footnote)
                        .foregroundColor(GHTheme.accent)
                    }
                }
            }

            if let banner = bannerRecord, showApprovalBanner {
                GHCard(pad: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your video has been accepted!")
                            .font(.headline)
                            .ghForeground(GHTheme.text)
                        let daysNote = banner.daysRemaining
                            .map { " Gallery access will be available for \($0) more days." } ?? ""
                        Text("You now have access to the event gallery. The gallery may be empty at first if you're among the first approved — it grows as the organizer reviews other submissions.\(daysNote)")
                            .font(.subheadline)
                            .ghForeground(GHTheme.muted)
                        Text("⚠️ Important: your gallery access is stored on this device. If you delete the GigHive app, you will permanently lose access to this gallery and it cannot be recovered.")
                            .font(.caption)
                            .ghForeground(GHTheme.muted)
                        HStack(spacing: 12) {
                            Button("View Event Gallery") {
                                showApprovalBanner = false
                                GuestUploadRecord.dismissBanner(nonce: banner.statusNonce)
                                goToBannerGallery = true
                            }
                            .buttonStyle(GHButtonStyle(color: GHTheme.accent))
                            Button("Done") {
                                showApprovalBanner = false
                                GuestUploadRecord.dismissBanner(nonce: banner.statusNonce)
                            }
                            .buttonStyle(GHButtonStyle(color: .gray))
                        }
                    }
                }
            }

            // Deduplicate by baseURLString+eventName: one row per event,
            // preferring approved records, then most recently submitted.
            let deduplicatedGalleries: [GuestUploadRecord] = {
                let approved = uploadRecords.filter { $0.approvalStatus == "approved" }
                var seen: Set<String> = []
                var result: [GuestUploadRecord] = []
                for record in approved {
                    let key = record.baseURLString + "|" + record.eventName
                    if seen.insert(key).inserted { result.append(record) }
                }
                return result
            }()
            if !deduplicatedGalleries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Event Galleries")
                        .font(.subheadline).bold()
                        .ghForeground(GHTheme.text)
                    ForEach(deduplicatedGalleries, id: \.statusNonce) { record in
                        let eventKey = record.baseURLString + "|" + record.eventName
                        let hasNewVideos = uploadRecords.contains {
                            $0.baseURLString + "|" + $0.eventName == eventKey &&
                            newVideoNonces.contains($0.statusNonce)
                        }
                        NavigationLink(destination: GuestGalleryView(record: record)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.eventName)
                                        .font(.subheadline)
                                        .ghForeground(GHTheme.text)
                                    if let days = record.daysRemaining {
                                        Text("Available for \(days) more days")
                                            .font(.caption)
                                            .ghForeground(GHTheme.muted)
                                    }
                                }
                                Spacer()
                                if hasNewVideos {
                                    Text("New videos")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .ghForeground(GHTheme.muted)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Text("To add more videos to an event, scan the event QR code again.")
                        .font(.caption)
                        .ghForeground(GHTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Hidden navigation links kept inside hierarchy for reliability on iOS 15
            NavigationLink(destination: LoginView(), isActive: $goToLogin) { EmptyView() }
                .frame(width: 0, height: 0)
                .hidden()
            NavigationLink(destination: UploadView(onUpload: { _ in 
                logWithTimestamp("[Splash] Upload finished callback")
            }), isActive: $goToUpload) { EmptyView() }
                .frame(width: 0, height: 0)
                .hidden()
            NavigationLink(destination: GuestUploadView(), isActive: $goToGuestUpload) { EmptyView() }
                .frame(width: 0, height: 0)
                .hidden()
            NavigationLink(
                destination: Group {
                    if let rec = bannerRecord { GuestGalleryView(record: rec) } else { EmptyView() }
                },
                isActive: $goToBannerGallery) { EmptyView() }
                .frame(width: 0, height: 0)
                .hidden()
            // goToDatabase no longer used with direct NavigationLink above but keep for safety
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .ghFullScreenBackground(GHTheme.bg)
            .onAppear { 
                logWithTimestamp("[Splash] appeared; loggedIn=\(session.credentials != nil)")
                if guestSession.rawToken != nil {
                    logWithTimestamp("[Splash] Guest token present, navigating to GuestUploadView")
                    goToGuestUpload = true
                } else if session.credentials != nil, session.intendedRoute == .upload {
                    logWithTimestamp("[Splash] Auto-navigating to Upload after login")
                    goToUpload = true
                    // Clear intended route so that Back from Upload returns to Splash cleanly
                    session.intendedRoute = nil
                }
                // Reload records synchronously so gallery navigation state (viewedUploadJobIds,
                // lastSeenVideoCount) is fresh before the async poll runs.
                let freshRecords = GuestUploadRecord.load()
                uploadRecords = freshRecords
                newVideoNonces = newVideoNonces.filter { nonce in
                    guard let r = freshRecords.first(where: { $0.statusNonce == nonce }) else { return false }
                    return r.viewedUploadJobIds.count < r.lastSeenVideoCount
                }
                Task { await pollGuestRecords() }
            }
            .onChange(of: guestSession.rawToken) { token in
                if token != nil {
                    logWithTimestamp("[Splash] Guest token set while app open, navigating to GuestUploadView")
                    goToGuestUpload = true
                } else {
                    goToGuestUpload = false
                }
            }
            .onChange(of: goToLogin) { newVal in logWithTimestamp("[Splash] goToLogin=\(newVal)") }
            .onChange(of: goToDatabase) { newVal in logWithTimestamp("[Splash] goToDatabase=\(newVal)") }
            .alert(isPresented: $showRejectionAlert) {
                Alert(
                    title: Text("Video not accepted"),
                    message: Text("Your video from \(rejectedEventName ?? "the event") was rejected by the moderator and not added to the gallery."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onReceive(splashTimer) { _ in
                guard scenePhase == .active else { return }
                Task { await pollGuestRecords() }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await pollGuestRecords() }
            }
            
            VStack {
                Spacer()
                HStack {
                    Text(AppVersion.versionString)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(8)
                    Spacer()
                }
            }
        }
    }

    @MainActor
    private func pollGuestRecords() async {
        var records = GuestUploadRecord.load()
        logWithTimestamp("[Splash] pollGuestRecords: found \(records.count) stored record(s)")
        for r in records {
            logWithTimestamp("[Splash]   record nonce=\(r.statusNonce.prefix(8))… status=\(r.approvalStatus) baseURL=\(r.baseURLString)")
        }
        uploadRecords = records

        let indicesToPoll = records.indices.filter {
            records[$0].approvalStatus == "pending" || records[$0].approvalStatus == "approved"
        }
        guard !indicesToPoll.isEmpty else { return }

        var results = [(idx: Int, resp: GuestStatusResponse?, err: Error?)](
            repeating: (idx: 0, resp: nil, err: nil), count: indicesToPoll.count
        )
        await withTaskGroup(of: (Int, GuestStatusResponse?, Error?).self) { group in
            for (slot, idx) in indicesToPoll.enumerated() {
                let record = records[idx]
                guard let baseURL = URL(string: record.baseURLString) else { continue }
                let nonce = record.statusNonce
                let client = GuestGalleryAPIClient(baseURL: baseURL)
                group.addTask {
                    do {
                        let resp = try await client.fetchStatus(nonce: nonce)
                        return (slot, resp, nil)
                    } catch {
                        return (slot, nil, error)
                    }
                }
            }
            for await (slot, resp, err) in group {
                results[slot] = (idx: indicesToPoll[slot], resp: resp, err: err)
            }
        }

        var newVideos: Set<String> = []
        var firstRejectedName: String?
        var noncesToRemove: Set<String> = []

        for (slot, result) in results.enumerated() {
            let idx = indicesToPoll[slot]
            guard let resp = result.resp else {
                if let err = result.err {
                    let nonce = records[idx].statusNonce
                    switch err {
                    case GuestGalleryError.badServer(let code) where code == 404:
                        logWithTimestamp("[Splash] poll: nonce=\(nonce.prefix(8))\u{2026} returned 404 \u{2014} removing stale record")
                        noncesToRemove.insert(nonce)
                    case GuestGalleryError.accessDenied:
                        logWithTimestamp("[Splash] poll: nonce=\(nonce.prefix(8))\u{2026} returned 403 (revoked) \u{2014} removing record")
                        noncesToRemove.insert(nonce)
                    default:
                        logWithTimestamp("[Splash] poll: nonce=\(nonce.prefix(8))\u{2026} transient error=\(err.localizedDescription) \u{2014} keeping record")
                    }
                }
                continue
            }
            let oldRecord = records[idx]

            if oldRecord.approvalStatus == "approved",
               let vc = resp.videoCount, vc > oldRecord.lastSeenVideoCount {
                newVideos.insert(oldRecord.statusNonce)
            }

            if resp.status == "rejected", firstRejectedName == nil {
                firstRejectedName = oldRecord.eventName
            }

            records[idx].approvalStatus = resp.status
            if let dr = resp.daysRemaining { records[idx].daysRemaining = dr }
        }

        if !noncesToRemove.isEmpty {
            records.removeAll { noncesToRemove.contains($0.statusNonce) }
            logWithTimestamp("[Splash] poll: removed \(noncesToRemove.count) stale record(s)")
        }
        GuestUploadRecord.save(records)
        uploadRecords = records
        newVideoNonces = newVideos

        if let name = firstRejectedName {
            rejectedEventName = name
            showRejectionAlert = true
        }

        let dismissed = GuestUploadRecord.loadDismissedBanners()
        if let banner = records.first(where: {
            $0.approvalStatus == "approved" && !dismissed.contains($0.statusNonce)
        }) {
            bannerRecord = banner
            showApprovalBanner = true
        }
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
            .environmentObject(AuthSession())
            .environmentObject(UploadStateStore())
            .environmentObject(GuestUploadSession())
    }
}
