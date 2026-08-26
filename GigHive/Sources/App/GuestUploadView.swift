import SwiftUI
import UniformTypeIdentifiers

struct GuestUploadView: View {
    @EnvironmentObject var guestSession: GuestUploadSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var fileURL: URL?
    @State private var isLoadingToken = false
    @State private var tokenError: String?
    @State private var isUploading = false
    @State private var uploadProgress: Double?
    @State private var showResultAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showPhotosPicker = false
    @State private var showFilesPicker = false
    @State private var isLoadingMedia = false
    @State private var photoCopyProgress: Double? = nil
    @State private var cancelPreparingMedia: (() -> Void)? = nil
    @State private var videoDisplayName: String? = nil
    @State private var videoSource = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image("beelogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: (UIFont.preferredFont(forTextStyle: .title2).pointSize + 2) * 2.66)
                    Text("Guest Upload")
                        .font(.title3).bold()
                        .ghForeground(GHTheme.text)
                }

                if isLoadingToken {
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: GHTheme.accent))
                        Text("Validating upload link…")
                            .font(.subheadline)
                            .ghForeground(GHTheme.muted)
                    }
                    .padding(.vertical, 8)

                } else if let error = tokenError {
                    // Step 23 — error / fallback screen
                    GHCard(pad: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upload link invalid")
                                .font(.headline)
                                .ghForeground(GHTheme.text)
                            Text(error)
                                .font(.subheadline)
                                .ghForeground(GHTheme.muted)
                            Text("It may have expired or been revoked by the event organizer.")
                                .font(.caption)
                                .ghForeground(GHTheme.muted)

                            Button("Open in Safari") {
                                let base = guestSession.baseURL?.absoluteString ?? "https://gighive.app"
                                let token = guestSession.rawToken ?? ""
                                if let url = URL(string: "\(base)/upload/\(token)") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(GHButtonStyle(color: .blue))
                        }
                    }

                } else if guestSession.rawToken == nil && !isUploading {
                    GHCard(pad: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upload received — thank you!")
                                .font(.headline)
                                .ghForeground(GHTheme.text)
                            Text("Your video is going into a queue for review. You will typically be notified in the app within 24\u{2013}48 hours once the event organizer has reviewed your submission. After which, you will be able to see your video along with all the other videos individuals like yourself have captured during the event. Please return to the app within 24\u{2013}48 hours to check on status.")
                                .font(.subheadline)
                                .ghForeground(GHTheme.muted)
                            Button("Done") {
                                presentationMode.wrappedValue.dismiss()
                            }
                            .buttonStyle(GHButtonStyle(color: GHTheme.accent))
                        }
                    }

                } else if let details = guestSession.eventDetails {
                    VStack(alignment: .leading, spacing: 16) {
                    if let token = guestSession.rawToken, let urlString = guestSession.baseURL?.absoluteString {
                        let viewerRecord = GuestUploadRecord(
                            statusNonce: token,
                            uploadJobId: 0,
                            eventName: "\(details.orgName) — \(details.eventDate)",
                            submittedAt: Date(),
                            baseURLString: urlString,
                            approvalStatus: "viewer",
                            lastSeenVideoCount: 0,
                            viewedUploadJobIds: [],
                            daysRemaining: nil
                        )
                        NavigationLink(destination: GuestGalleryView(record: viewerRecord)) {
                            GHCard(pad: 12) {
                                HStack(spacing: 8) {
                                    Image("beelogo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: (UIFont.preferredFont(forTextStyle: .title2).pointSize + 2) * 2.66)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Visit Event Gallery")
                                            .font(.title3).bold()
                                            .ghForeground(GHTheme.text)
                                        Text("\(details.orgName) — \(details.eventDate)")
                                            .font(.caption)
                                            .ghForeground(GHTheme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .ghForeground(GHTheme.muted)
                                }
                            }
                        }
                        .disabled(isUploading)
                    }
                    // Main upload form — event details pre-populated, read-only
                    GHCard(pad: 10) {
                        VStack(alignment: .leading, spacing: 10) {

                            VStack(alignment: .leading, spacing: 4) {
                                GHLabel(text: "Event")
                                Text(details.orgName)
                                    .font(.body)
                                    .ghForeground(GHTheme.text)
                                Text(details.eventDate)
                                    .font(.caption)
                                    .ghForeground(GHTheme.muted)
                                if let title = details.title, !title.isEmpty {
                                    Text(title)
                                        .font(.caption)
                                        .ghForeground(GHTheme.muted)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                GHLabel(text: "Your name *")
                                NoAccessoryTextField(
                                    text: $guestSession.displayName,
                                    placeholder: "e.g. Jane Smith",
                                    keyboardType: .default,
                                    autocapitalizationType: .words,
                                    autocorrectionType: .default
                                )
                                .onChange(of: guestSession.displayName) { value in
                                    if value.count > 100 {
                                        guestSession.displayName = String(value.prefix(100))
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .ghBackgroundMaterial()
                                .cornerRadius(6)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                GHLabel(text: "Clip label (optional)")
                                NoAccessoryTextField(
                                    text: $guestSession.clipLabel,
                                    placeholder: "e.g. First song, Crowd shot",
                                    keyboardType: .default,
                                    autocapitalizationType: .sentences,
                                    autocorrectionType: .default
                                )
                                .onChange(of: guestSession.clipLabel) { value in
                                    if value.count > 255 {
                                        guestSession.clipLabel = String(value.prefix(255))
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .ghBackgroundMaterial()
                                .cornerRadius(6)
                                Text("Files are stored under a unique name for privacy. Your label helps you identify the clip in the gallery.")
                                    .font(.caption2)
                                    .ghForeground(GHTheme.muted)
                            }

                            Toggle(isOn: $guestSession.tosAccepted) {
                                VStack(alignment: .leading, spacing: 2) {
                                    GHLabel(text: "I accept the Terms of Service *")
                                    Text("By uploading, you confirm you have the right to share this content.")
                                        .font(.caption2)
                                        .ghForeground(GHTheme.muted)
                                }
                            }
                            .ghTint(GHTheme.accent)

                            Text("You’re on the honor system — please don’t upload abusive, pornographic, violent, or otherwise inappropriate content. Uploads are reviewed by the event organizer and may be removed.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.vertical, 4)

                            Text("Max upload size: \(AppConstants.MAX_UPLOAD_SIZE_FORMATTED)")
                                .font(.caption2)
                                .ghForeground(GHTheme.muted)

                            Text("Tip: Videos stored in iCloud must download and export before uploading. For a 12-minute 4K video this may take 5–10 minutes. Verify large video sizes before selecting.")
                                .font(.caption2)
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 6) {
                                GHLabel(text: "Video file *")
                                Menu {
                                    Button("From Photos") {
                                        videoSource = "From Photos"
                                        showPhotosPicker = true
                                    }
                                    Button("From Files") {
                                        videoSource = "From Files"
                                        isLoadingMedia = true
                                        showFilesPicker = true
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "paperclip")
                                        Text(videoDisplayName ?? "Choose Video")
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(GHTheme.accent, lineWidth: 1.5)
                                            .background(GHTheme.card.opacity(0.3))
                                    )
                                    .cornerRadius(10)
                                }
                            .disabled(isLoadingMedia)
                            if isLoadingMedia {
                                HStack(spacing: 8) {
                                    if let progress = photoCopyProgress {
                                        ProgressView(value: progress)
                                            .progressViewStyle(LinearProgressViewStyle(tint: GHTheme.accent))
                                    } else {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: GHTheme.accent))
                                    }
                                    Text(photoCopyProgress.map { "Loading… \(Int($0 * 100))%" } ?? "Loading video…")
                                        .font(.caption)
                                        .ghForeground(GHTheme.muted)
                                    Spacer()
                                    Button("Cancel") {
                                        cancelPreparingMedia?()
                                        isLoadingMedia = false
                                        photoCopyProgress = nil
                                        cancelPreparingMedia = nil
                                        videoDisplayName = nil
                                    }
                                    .font(.caption)
                                    .ghForeground(GHTheme.accent)
                                }
                                .padding(.vertical, 4)
                                Text("Do not navigate away from this screen or the file load will be cancelled.")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            }

                            if isUploading {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        if let progress = uploadProgress {
                                            ProgressView(value: progress)
                                                .scaleEffect(0.8)
                                                .progressViewStyle(LinearProgressViewStyle(tint: GHTheme.accent))
                                                .frame(width: 40)
                                        } else {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .progressViewStyle(CircularProgressViewStyle(tint: GHTheme.accent))
                                        }
                                        Text(uploadProgress.map { "Uploading… \(Int($0 * 100))%" } ?? "Uploading…")
                                            .font(.caption)
                                            .ghForeground(GHTheme.muted)
                                    }
                                    Text("Do not navigate away from this page or your upload will be cancelled.")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                .padding(.vertical, 4)
                            }

                            Button(isUploading ? "Uploading…" : "Upload") {
                                Task { await doUpload() }
                            }
                            .buttonStyle(GHButtonStyle(color: GHTheme.accent))
                            .disabled(isUploading || isLoadingMedia || fileURL == nil || !guestSession.tosAccepted || guestSession.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .padding(.top, 2)

                            if !isUploading && !isLoadingMedia {
                                let missing = missingFields()
                                if !missing.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(missing, id: \.self) { msg in
                                            Text("⚠️ \(msg)")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                    }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
        .dismissKeyboardOnScroll()
        .ghFullScreenBackground(GHTheme.bg)
        // .onAppear fires on first appearance; .onChange re-fires when rawToken changes
        // (e.g. user scans a second QR code while GuestUploadView is already on the stack).
        .onAppear {
            if guestSession.displayName.isEmpty {
                guestSession.displayName = UIDevice.current.name
            }
            Task { await validateToken() }
        }
        .onChange(of: guestSession.rawToken) { _ in
            Task { await validateToken() }
        }
        .sheet(isPresented: $showPhotosPicker) {
            PHPickerView(
                selectionHandler: { url in
                    // url is nil on cancel or too-large rejection; non-nil on success.
                    // Setting fileURL = nil on cancel discards any previously loaded file — intentional, mirrors UploadView.
                    showPhotosPicker = false
                    fileURL = url
                    isLoadingMedia = false
                    photoCopyProgress = nil
                    cancelPreparingMedia = nil
                    videoDisplayName = url.map { u in
                        let size = formattedFileSize(u)
                        return size.isEmpty ? videoSource : "\(videoSource) · \(size)"
                    }
                },
                onFileTooLarge: { fileSize, maxSize in
                    showPhotosPicker = false
                    isLoadingMedia = false
                    photoCopyProgress = nil
                    cancelPreparingMedia = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        alertTitle = "File Too Large"
                        alertMessage = "The selected file (\(fileSize)) exceeds the maximum allowed upload size of \(maxSize). Please select a smaller file or compress the video before uploading."
                        showResultAlert = true
                    }
                },
                onCopyStarted: {
                    isLoadingMedia = true
                    photoCopyProgress = nil
                },
                onCopyProgress: { progress in
                    photoCopyProgress = progress
                },
                onCopyCancelAvailable: { cancel in
                    cancelPreparingMedia = cancel
                },
                onLoadError: { message in
                    showPhotosPicker = false
                    isLoadingMedia = false
                    photoCopyProgress = nil
                    cancelPreparingMedia = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        alertTitle = "Video Load Failed"
                        alertMessage = message
                        showResultAlert = true
                    }
                }
            )
            .modifier(PresentationDetentsCompat())
        }
        .sheet(isPresented: $showFilesPicker) {
            DocumentPickerView(
                allowedTypes: [UTType.movie, UTType.mpeg4Movie],
                onPick: { url in
                    showFilesPicker = false
                    fileURL = url
                    isLoadingMedia = false
                    videoDisplayName = url.map { u in
                        let size = formattedFileSize(u)
                        return size.isEmpty ? videoSource : "\(videoSource) · \(size)"
                    }
                },
                onFileTooLarge: { fileSize, maxSize in
                    showFilesPicker = false
                    isLoadingMedia = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        alertTitle = "File Too Large"
                        alertMessage = "The selected file (\(fileSize)) exceeds the maximum allowed upload size of \(maxSize). Please select a smaller file or compress the video before uploading."
                        showResultAlert = true
                    }
                }
            )
            .modifier(PresentationDetentsCompat())
        }
        .alert(isPresented: $showResultAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK")) {
                    if guestSession.rawToken == nil {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            )
        }
    }

    @MainActor
    private func validateToken() async {
        guard let token = guestSession.rawToken,
              let base = guestSession.baseURL else {
            logWithTimestamp("[GuestUpload] validateToken: BAIL — rawToken=\(guestSession.rawToken == nil ? "nil" : "set") baseURL=\(guestSession.baseURL?.absoluteString ?? "nil")")
            return
        }
        logWithTimestamp("[GuestUpload] validateToken: baseURL=\(base) token=\(token.prefix(8))…")
        tokenError = nil
        isLoadingToken = true
        do {
            guestSession.eventDetails = try await QRTokenAPIClient(baseURL: base).validateToken(token)
            logWithTimestamp("[GuestUpload] validateToken: SUCCESS eventDetails=\(guestSession.eventDetails != nil)")
        } catch {
            logWithTimestamp("[GuestUpload] validateToken: ERROR type=\(type(of: error)) code=\((error as NSError).code) domain=\((error as NSError).domain) desc=\(error.localizedDescription)")
            logWithTimestamp("[GuestUpload] validateToken: full error=\(error)")
            tokenError = error.localizedDescription
        }
        isLoadingToken = false
    }

    private func formattedFileSize(_ url: URL) -> String {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64,
              size > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func missingFields() -> [String] {
        var msgs: [String] = []
        if guestSession.displayName.trimmingCharacters(in: .whitespaces).isEmpty { msgs.append("Please enter your name") }
        if !guestSession.tosAccepted { msgs.append("Please accept the Terms of Service") }
        if fileURL == nil { msgs.append("Please select a video file") }
        return msgs
    }

    @MainActor
    private func doUpload() async {
        guard let fileURL,
              let baseURL = guestSession.baseURL,
              let rawToken = guestSession.rawToken,
              let eventDetails = guestSession.eventDetails,
              guestSession.tosAccepted else { return }

        let payload = UploadPayload.forGuestUpload(
            fileURL: fileURL,
            eventDetails: eventDetails,
            displayName: guestSession.displayName,
            clipLabel: guestSession.clipLabel
        )

        let client = UploadClient(
            baseURL: baseURL,
            sessionCredential: nil,
            uploadToken: rawToken,
            useBackgroundSession: false,
            allowInsecure: false
        )

        isUploading = true
        uploadProgress = nil

        defer {
            isUploading = false
            uploadProgress = nil
        }

        do {
            let (status, data, _) = try await client.uploadWithMultipartInputStream(payload, progress: { done, total in
                guard total > 0 else { return }
                Task { @MainActor in
                    uploadProgress = Double(done) / Double(total)
                }
            })
            handleFinalizeResponse(status: status, data: data, host: baseURL.host ?? "")
        } catch is CancellationError {
            alertTitle = "Cancelled"
            alertMessage = "Upload was cancelled."
            showResultAlert = true
        } catch {
            alertTitle = "Upload Failed"
            alertMessage = error.localizedDescription
            showResultAlert = true
        }
    }

    @MainActor
    private func handleFinalizeResponse(status: Int, data: Data, host: String) {
        switch status {
        case 200, 201:
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            logWithTimestamp("[GuestUpload] Finalize raw body: \(rawBody)")
            let resp: FinalizeResponse? = {
                if let r = try? JSONDecoder().decode(FinalizeResponse.self, from: data) { return r }
                guard let bodyText = String(data: data, encoding: .utf8),
                      let candidate = extractJSONCandidate(bodyText),
                      let candData = candidate.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(FinalizeResponse.self, from: candData)
            }()
            logWithTimestamp("[GuestUpload] Finalize decoded: resp=\(resp != nil), statusNonce=\(resp?.statusNonce ?? "nil"), uploadJobId=\(resp?.uploadJobId.map { String($0) } ?? "nil")")
            if let resp = resp {
                let token = resp.deleteToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !token.isEmpty, !host.isEmpty {
                    let entry = UploadedFileTokenEntry(
                        fileId: resp.id,
                        deleteToken: token,
                        createdAt: Date(),
                        eventDate: resp.eventDate ?? "",
                        orgName: resp.orgName ?? "",
                        eventType: resp.eventType ?? "",
                        label: resp.label,
                        fileName: resp.fileName,
                        fileType: resp.fileType
                    )
                    try? UploaderDeleteTokenStore.upsert(host: host, entry: entry)
                }
                if let nonce = resp.statusNonce, let jobId = resp.uploadJobId {
                    let eventName = guestSession.eventDetails
                        .map { "\($0.orgName) — \($0.eventDate)" } ?? "Event"
                    let record = GuestUploadRecord(
                        statusNonce: nonce,
                        uploadJobId: jobId,
                        eventName: eventName,
                        submittedAt: Date(),
                        baseURLString: guestSession.baseURL?.absoluteString ?? "",
                        approvalStatus: "pending",
                        lastSeenVideoCount: 0,
                        viewedUploadJobIds: [],
                        daysRemaining: nil
                    )
                    GuestUploadRecord.upsert(record)
                    logWithTimestamp("[GuestUpload] GuestUploadRecord upserted: nonce=\(nonce) jobId=\(jobId) baseURL=\(guestSession.baseURL?.absoluteString ?? "nil")")
                } else {
                    logWithTimestamp("[GuestUpload] ⚠️ statusNonce or uploadJobId missing — record NOT persisted")
                }
            } else {
                logWithTimestamp("[GuestUpload] ⚠️ FinalizeResponse decode failed entirely")
            }
            guestSession.clear()
            guestSession.recentUploadSuccess = true
        case 404:
            alertTitle = "Link Expired"
            alertMessage = "This upload link is no longer valid. Please ask the event organizer for a new QR code."
            showResultAlert = true
        case 400:
            alertTitle = "Invalid Request"
            alertMessage = String(data: data, encoding: .utf8) ?? "Bad request"
            showResultAlert = true
        case 409:
            alertTitle = "Already Uploaded"
            alertMessage = "Video already uploaded to this event (HTTP 409, duplicate checksum). Upload unnecessary."
            showResultAlert = true
        default:
            alertTitle = "HTTP \(status)"
            alertMessage = String(data: data, encoding: .utf8) ?? ""
            showResultAlert = true
        }
    }
}

struct GuestUploadView_Previews: PreviewProvider {
    static var previews: some View {
        GuestUploadView()
            .environmentObject(GuestUploadSession())
    }
}
