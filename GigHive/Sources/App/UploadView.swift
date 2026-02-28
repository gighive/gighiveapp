import SwiftUI
import UniformTypeIdentifiers
import Foundation

// Helper struct for file size error state
struct FileSizeError: Equatable {
    let fileSize: String
    let maxSize: String
}

struct LabeledField<Content: View>: View {
    let label: String
    let helper: String?
    @ViewBuilder var content: Content

    init(_ label: String, helper: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.helper = helper
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GHLabel(text: label)
            content
            if let helper, !helper.isEmpty {
                Text(helper).font(.footnote).ghForeground(GHTheme.muted)
            }
        }
    }
}

struct UploadView: View {
    @EnvironmentObject var session: AuthSession
    // SERVER
    @AppStorage("gh_server_url") private var serverURLString: String = "https://gighive" // editable by user
    @AppStorage("gh_basic_user") private var username: String = ""
    @AppStorage("gh_basic_pass") private var password: String = ""
    @AppStorage("gh_eventType_default") private var storedEventType: String = "band"

    @State private var fileURL: URL?
    @State private var eventDate = Date()
    @State private var orgName = ""
    @State private var eventType = "band"
    @State private var label = ""
    @State private var autogenLabel = false
    @State private var showPhotosPicker = false
    @State private var showFilesPicker = false
    @State private var isUploading = false
    @State private var isCancelling = false
    @State private var showResultAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var debugLog: [String] = []
    @State private var successURL: URL?
    @State private var failureCount: Int = 0
    @State private var uploadTask: Task<Void, Never>? = nil
    @State private var lastButtonStatus: String? = nil
    @State private var currentUploadClient: UploadClient? = nil
    @State private var allowInsecureTLS = false
    @State private var isLoadingMedia = false
    @State private var cancelPreparingMedia: (() -> Void)? = nil
    @State private var loadedFileSize: String? = nil
    // Ensure loading text is visible for at least a minimum duration
    @State private var mediaLoadingStartedAt: Date? = nil
    @State private var lastProgressBucket: Int = 0
    @State private var pendingFileSizeError: FileSizeError? = nil
    @State private var photoCopyProgress: Double? = nil  // 0.0 to 1.0 for Photos copy progress
    @State private var uploadProgress: Double? = nil  // 0.0 to 1.0 for upload progress
    @State private var myUploadsOnDevice: [UploadedFileTokenEntry] = []
    @State private var pendingDeleteEntry: UploadedFileTokenEntry? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var invalidTokenEntry: UploadedFileTokenEntry? = nil
    @State private var showInvalidTokenPrompt: Bool = false
    @State private var deleteErrorMessage: String? = nil
    @State private var showDeleteErrorAlert: Bool = false

    private struct FinalizeResponse: Codable {
        let id: Int
        let fileName: String?
        let fileType: String?
        let mimeType: String?
        let sizeBytes: Int?
        let checksumSha256: String?
        let eventDate: String?
        let orgName: String?
        let eventType: String?
        let label: String?
        let deleteToken: String?

        enum CodingKeys: String, CodingKey {
            case id
            case fileName = "file_name"
            case fileType = "file_type"
            case mimeType = "mime_type"
            case sizeBytes = "size_bytes"
            case checksumSha256 = "checksum_sha256"
            case eventDate = "event_date"
            case orgName = "org_name"
            case eventType = "event_type"
            case label
            case deleteToken = "delete_token"
        }
    }

    let onUpload: (UploadPayload) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image("beelogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: (UIFont.preferredFont(forTextStyle: .title2).pointSize + 2) * 2.66)
                    Text("Gighive Upload")
                        .font(.title3).bold()
                        .ghForeground(GHTheme.text)
                }
                // Logged-in banner
                if let creds = session.credentials {
                    Text("User is logged into \(session.baseURL?.absoluteString ?? "<unknown>") as \(creds.user)")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }

                GHCard(pad: 8) {
                    VStack(alignment: .leading, spacing: 6) {

                        LabeledField("Media file (audio/video) *") {
                            Menu {
                                Button("From Files", action: { 
                                    loadedFileSize = nil  // Clear previous file size
                                    isLoadingMedia = true  // Show loading immediately when dropdown option is touched
                                    showFilesPicker = true 
                                })
                                Button("From Photos", action: { 
                                    loadedFileSize = nil  // Clear previous file size
                                    // Don't set isLoadingMedia here - it will be set when copy starts via onCopyStarted callback
                                    showPhotosPicker = true 
                                })
                            } label: {
                                HStack {
                                    Image(systemName: "paperclip")
                                    Text(fileURL?.lastPathComponent ?? "Choose File")
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
                            if isLoadingMedia || (fileURL != nil && loadedFileSize == nil) {
                                HStack(spacing: 8) {
                                    if let progress = photoCopyProgress {
                                        ProgressView(value: progress)
                                            .scaleEffect(0.8)
                                            .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.7, green: 0.6, blue: 0.9)))
                                            .frame(width: 40)
                                    } else {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.7, green: 0.6, blue: 0.9)))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let progress = photoCopyProgress {
                                            Text("Preparing video from Photos... \(Int(progress * 100))%")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                                .bold()
                                        } else {
                                            Text("Preparing video from Photos...")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                                .bold()
                                        }
                                        Text("Converting video to H.264 format for compatibility. This may take a few minutes for large videos.\n\nTo avoid this going forward: Change iPhone Settings → Camera → Formats → \"Most Compatible\"")
                                            .font(.caption2)
                                            .foregroundColor(.orange.opacity(0.8))
                                    }
                                }
                                .padding(.vertical, 4)
                            } else if let fileSize = loadedFileSize {
                                Text("File size: \(fileSize)")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .bold()
                            }
                        }

                        LabeledField("Event date *") {
                            DatePicker("", selection: $eventDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(CompactDatePickerStyle())
                                .ghForeground(GHTheme.text)
                                .environment(\.colorScheme, .dark)
                        }

                        LabeledField("Band or wedding party name *") {
                            NoAccessoryTextField(
                                text: $orgName,
                                placeholder: "",
                                keyboardType: .default,
                                autocapitalizationType: .words,
                                autocorrectionType: .no
                            )
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .ghBackgroundMaterial()
                            .cornerRadius(6)
                        }

                        LabeledField("Event type *") {
                            Picker("", selection: $eventType) {
                                Text("band").tag("band")
                                Text("wedding").tag("wedding")
                            }
                            .pickerStyle(.segmented)
                        }

                        LabeledField("Song title or wedding table / identifier *") {
                            NoAccessoryTextField(
                                text: $label,
                                placeholder: "",
                                keyboardType: .default,
                                autocapitalizationType: .none,
                                autocorrectionType: .no
                            )
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .ghBackgroundMaterial()
                            .cornerRadius(6)
                        }

                        Toggle(isOn: $autogenLabel) {
                            GHLabel(text: "Autogenerate label?")
                        }
                        .ghTint(GHTheme.accent)

                        if autogenLabel {
                            Text("If checked, the label will be set to \"Auto YYYY-MM-DD\" based on the Event date.")
                                .ghForeground(GHTheme.muted)
                        }

                        Button(isCancelling ? "Cancelling…" : (isUploading ? "Uploading…" : (isLoadingMedia ? "Cancel" : (lastButtonStatus ?? "Upload"))), action: {
                            if isUploading {
                                // Second press: cancel
                                isCancelling = true
                                debugLog.append("cancelling…")
                                uploadTask?.cancel()
                                
                                // Also cancel the underlying network upload task
                                currentUploadClient?.cancelCurrentUpload()
                            } else if isLoadingMedia {
                                logWithTimestamp("🛑 [UploadView] Cancel pressed during media preparation")
                                debugLog.append("cancel pressed during media preparation")

                                if let cancel = cancelPreparingMedia {
                                    logWithTimestamp("🛑 [UploadView] Invoking cancelPreparingMedia")
                                    cancel()
                                } else {
                                    logWithTimestamp("⚠️ [UploadView] cancelPreparingMedia is nil (no cancel hook installed yet)")
                                }

                                // Reset UI state immediately; picker layer will also clear selection via selectionHandler(nil)
                                cancelPreparingMedia = nil
                                isLoadingMedia = false
                                photoCopyProgress = nil
                                mediaLoadingStartedAt = nil
                            } else {
                                doUpload()
                            }
                        })
                            .buttonStyle(GHButtonStyle(color: lastButtonStatus == "Upload Cancelled" ? .red : GHTheme.accent))
                            .disabled((!isUploading && !isLoadingMedia) && (fileURL == nil || (label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                            .padding(.top, 2)

                        // Validation messages for mandatory fields
                        if !isUploading && !isLoadingMedia {
                            let validationMessages = getValidationMessages()
                            if !validationMessages.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(validationMessages, id: \.self) { message in
                                        Text("⚠️ \(message)")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }

                        // Upload progress indicator (similar to photo copy progress)
                        if isUploading {
                            HStack(spacing: 8) {
                                if let progress = uploadProgress {
                                    ProgressView(value: progress)
                                        .scaleEffect(0.8)
                                        .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.7, green: 0.6, blue: 0.9)))
                                        .frame(width: 40)
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.7, green: 0.6, blue: 0.9)))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    if let progress = uploadProgress {
                                        Text("Uploading video... \(Int(progress * 100))%")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                            .bold()
                                    } else {
                                        Text("Uploading video...")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                            .bold()
                                    }
                                    Text("Feel free to use other apps, your upload will continue in the background.")
                                        .font(.caption2)
                                        .foregroundColor(.orange.opacity(0.8))
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if !debugLog.isEmpty {
                            Text(debugLog.joined(separator: " → "))
                                .font(.caption2)
                                .foregroundColor(.red)
                                .padding(.top, 2)
                        }


                        if successURL != nil {
                            NavigationLink(destination: DatabaseView()) {
                                Text("View in Database")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(GHButtonStyle(color: .green))
                            .padding(.top, 8)
                        }

                        // Cert-bypass is controlled globally via session; no toggle here.

                        GHCard(pad: 8) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("My uploads from this device")
                                    .font(.title3)
                                    .bold()
                                    .ghForeground(GHTheme.text)

                                if myUploadsOnDevice.isEmpty {
                                    Text("No uploads from this device yet.")
                                        .font(.footnote)
                                        .ghForeground(GHTheme.muted)
                                } else {
                                    Text("These entries exist because this device saved a delete token at upload time.")
                                        .font(.footnote)
                                        .ghForeground(GHTheme.muted)

                                    ForEach(myUploadsOnDevice) { entry in
                                        VStack(alignment: .leading, spacing: 6) {
                                            if !entry.eventDate.isEmpty {
                                                Text(entry.eventDate)
                                                    .font(.caption)
                                                    .ghForeground(GHTheme.muted)
                                            }

                                            if !entry.orgName.isEmpty {
                                                Text(entry.orgName)
                                                    .font(.headline)
                                                    .ghForeground(GHTheme.text)
                                            }

                                            HStack(alignment: .firstTextBaseline) {
                                                if let label = entry.label, !label.isEmpty {
                                                    Text(label)
                                                        .font(.subheadline)
                                                        .ghForeground(GHTheme.muted)
                                                } else if let fileName = entry.fileName, !fileName.isEmpty {
                                                    Text(fileName)
                                                        .font(.subheadline)
                                                        .ghForeground(GHTheme.muted)
                                                }
                                                Spacer()
                                                Text("File ID \(entry.fileId)")
                                                    .font(.caption2)
                                                    .ghForeground(GHTheme.muted)
                                            }

                                            Button("Delete") {
                                                logWithTimestamp("[UploadView] Delete tapped file_id=\(entry.fileId)")
                                                pendingDeleteEntry = entry
                                                showDeleteConfirm = true
                                            }
                                            .buttonStyle(GHButtonStyle(color: .red))
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }

                        Button(action: hideKeyboard) {
                            Text("Hide Keyboard").font(.caption)
                        }
                        .padding(.top, 2)

                        if failureCount >= 5 {
                            if let mail = makeSupportEmailLink() {
                                Link("Email administrator with debug log", destination: mail)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(8)
        }
        .ghFullScreenBackground(GHTheme.bg)
        .sheet(isPresented: $showPhotosPicker) {
            PHPickerView(selectionHandler: { url in
                // Clear old debug log when selecting new file
                debugLog = []

                if let url = url {
                    // Don't set isLoadingMedia here - it gets interrupted by picker dismissal
                    // Instead, set fileURL and let .onChange() handle the loading state
                    logWithTimestamp("📸 [PHPicker] File selected, setting fileURL")
                    self.loadedFileSize = nil
                    self.fileURL = url
                    self.showPhotosPicker = false
                    self.cancelPreparingMedia = nil
                    debugLog.append("file selected from Photos")
                } else {
                    // User cancelled
                    self.showPhotosPicker = false
                    self.fileURL = nil
                    self.loadedFileSize = nil
                    self.isLoadingMedia = false
                    self.cancelPreparingMedia = nil
                    debugLog.append("photos canceled")
                }
            }, onFileTooLarge: { fileSize, maxSize in
                // Dismiss picker first, then set error state
                logWithTimestamp("🚫 [PHPicker] onFileTooLarge callback fired: \(fileSize) > \(maxSize)")
                debugLog.append("file rejected: \(fileSize) > \(maxSize)")
                self.showPhotosPicker = false
                logWithTimestamp("🚫 [PHPicker] Dismissed picker sheet")
                // Delay setting error until after picker dismisses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    logWithTimestamp("🚫 [PHPicker] Setting pendingFileSizeError state")
                    self.pendingFileSizeError = FileSizeError(fileSize: fileSize, maxSize: maxSize)
                    logWithTimestamp("🚫 [PHPicker] pendingFileSizeError set to: \(String(describing: self.pendingFileSizeError))")
                }
            }, onCopyStarted: {
                // File copy from Photos has started - show progress immediately
                logWithTimestamp("📸 [PHPicker] onCopyStarted - showing progress indicator")
                self.isLoadingMedia = true
                self.mediaLoadingStartedAt = Date()
                self.loadedFileSize = nil
                self.photoCopyProgress = nil
                debugLog.append("copying file from Photos...")
            }, onCopyProgress: { progress in
                // Update progress during copy
                self.photoCopyProgress = progress
            }, onCopyCancelAvailable: { cancel in
                if cancel == nil {
                    logWithTimestamp("🧹 [UploadView] Received nil cancel hook (clearing)")
                } else {
                    logWithTimestamp("🧷 [UploadView] Received cancel hook (installing)")
                }
                self.cancelPreparingMedia = cancel
            })
            .modifier(PresentationDetentsCompat())
        }
        .sheet(isPresented: $showFilesPicker) {
            DocumentPickerView(
                allowedTypes: [
                    UTType.movie,
                    UTType.mpeg4Movie,
                    UTType.audio,
                    UTType.mp3
                ],
                onPick: { url in
                    // Clear old debug log when selecting new file
                    debugLog = []

                    // Show loading immediately upon a valid selection, then dismiss picker
                    if let url = url {
                        // Mark the start moment and show loading immediately
                        self.mediaLoadingStartedAt = Date()
                        self.isLoadingMedia = true
                        self.loadedFileSize = nil
                        self.fileURL = url
                        self.showFilesPicker = false
                        debugLog.append("reading file metadata...")

                        // Compute file size and only clear loading after minimum visible duration
                        DispatchQueue.global(qos: .userInitiated).async {
                            debugLog.append("calculating file size...")
                            let minVisible: TimeInterval = 1.0
                            let sizeText: String = {
                                do {
                                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                                    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                                } catch {
                                    return "unknown"
                                }
                            }()
                            let started = self.mediaLoadingStartedAt ?? Date()
                            let elapsed = Date().timeIntervalSince(started)
                            let remaining = max(0, minVisible - elapsed)
                            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                                self.loadedFileSize = sizeText
                                self.isLoadingMedia = false
                                self.mediaLoadingStartedAt = nil
                                debugLog.append("file metadata loaded (\(sizeText))")
                                debugLog.append("picked from Files")
                            }
                        }
                    } else {
                        // User cancelled
                        self.showFilesPicker = false
                        self.fileURL = nil
                        self.loadedFileSize = nil
                        self.isLoadingMedia = false
                        debugLog.append("files canceled")
                    }
                },
                onFileTooLarge: { fileSize, maxSize in
                    // Dismiss picker first, then set error state
                    logWithTimestamp("🚫 [DocumentPicker] onFileTooLarge callback fired: \(fileSize) > \(maxSize)")
                    debugLog.append("file rejected: \(fileSize) > \(maxSize)")
                    self.showFilesPicker = false
                    logWithTimestamp("🚫 [DocumentPicker] Dismissed picker sheet")
                    // Delay setting error until after picker dismisses
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        logWithTimestamp("🚫 [DocumentPicker] Setting pendingFileSizeError state")
                        self.pendingFileSizeError = FileSizeError(fileSize: fileSize, maxSize: maxSize)
                        logWithTimestamp("🚫 [DocumentPicker] pendingFileSizeError set to: \(String(describing: self.pendingFileSizeError))")
                    }
                }
            )
            .modifier(PresentationDetentsCompat())
        }
        .onChange(of: fileURL) { newURL in
            // Handle file selection from Photos picker
            // This runs AFTER picker dismisses, so UI updates work properly
            guard let newURL = newURL else {
                // File was cleared
                logWithTimestamp("📸 [onChange(fileURL)] File cleared")
                return
            }
            
            // Only show loading if we don't have a file size yet
            // (Files picker is fast and doesn't need progress)
            guard loadedFileSize == nil else {
                logWithTimestamp("📸 [onChange(fileURL)] File size already loaded, skipping progress")
                return
            }
            
            logWithTimestamp("📸 [onChange(fileURL)] New file selected, starting progress after delay")
            // Small delay to ensure picker sheet is fully dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                logWithTimestamp("📸 [onChange(fileURL)] Showing loading indicator")
                self.isLoadingMedia = true
                self.mediaLoadingStartedAt = Date()
                debugLog.append("reading file metadata...")
                
                // Compute file size on background thread
                DispatchQueue.global(qos: .userInitiated).async {
                    debugLog.append("calculating file size...")
                    let minVisible: TimeInterval = 1.0
                    let sizeText: String = {
                        do {
                            let bytes = try newURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                        } catch {
                            return "unknown"
                        }
                    }()
                    let started = self.mediaLoadingStartedAt ?? Date()
                    let elapsed = Date().timeIntervalSince(started)
                    let remaining = max(0, minVisible - elapsed)
                    logWithTimestamp("📸 [Background] File size calculated: \(sizeText), elapsed: \(elapsed)s, remaining: \(remaining)s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                        logWithTimestamp("📸 [Background] Updating UI with file size")
                        self.loadedFileSize = sizeText
                        self.isLoadingMedia = false
                        self.mediaLoadingStartedAt = nil
                        debugLog.append("file metadata loaded (\(sizeText))")
                    }
                }
            }
        }
        .onChange(of: pendingFileSizeError) { error in
            // Trigger alert when file size error is set, with delay to allow picker to fully dismiss
            logWithTimestamp("🔔 [onChange] pendingFileSizeError changed to: \(String(describing: error))")
            guard let error = error else { 
                logWithTimestamp("🔔 [onChange] Error is nil, returning")
                return 
            }
            logWithTimestamp("🔔 [onChange] Scheduling alert with 0.6s delay")
            let fileSize = error.fileSize
            let maxSize = error.maxSize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                logWithTimestamp("🔔 [onChange] Showing alert now")
                // Ensure we fully clear the selection and preparation state so the user cannot proceed
                // with an oversize file.
                self.showPhotosPicker = false
                self.showFilesPicker = false
                self.fileURL = nil
                self.loadedFileSize = nil
                self.isLoadingMedia = false
                self.photoCopyProgress = nil
                self.mediaLoadingStartedAt = nil
                self.cancelPreparingMedia = nil

                self.alertTitle = "File Too Large"
                self.alertMessage = "The selected file (\(fileSize)) exceeds the maximum allowed size of \(maxSize).\n\nPlease select a smaller file or compress the video before uploading."
                self.showResultAlert = true
                logWithTimestamp("🔔 [onChange] showResultAlert set to true")
                self.pendingFileSizeError = nil  // Clear after showing
                logWithTimestamp("🔔 [onChange] Cleared pendingFileSizeError")
            }
        }
        .onChange(of: autogenLabel) { on in if on { label = autoLabel() }; resetCancelledStatus() }
        .onChange(of: eventDate) { _ in if autogenLabel { label = autoLabel() }; resetCancelledStatus() }
        .onChange(of: eventType) { newValue in
            // Persist META selection across app launches
            storedEventType = newValue
            resetCancelledStatus()
        }
        .onChange(of: fileURL) { _ in resetCancelledStatus() }
        .onChange(of: orgName) { _ in resetCancelledStatus() }
        .onChange(of: label) { _ in resetCancelledStatus() }
        .onAppear {
            // Initialize META picker from the last used value
            eventType = storedEventType
            // Sync TLS toggle from shared session (authority for cert-bypass)
            allowInsecureTLS = session.allowInsecureTLS
            reloadMyUploadsOnDevice()
        }
        .sheet(isPresented: $showDeleteConfirm) {
            ZStack {
                GHTheme.bg.ignoresSafeArea()
                VStack {
                    Spacer()
                    GHCard(pad: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Delete this upload?")
                                .font(.headline)
                                .ghForeground(GHTheme.text)
                            Text("This will delete the uploaded file from the server.")
                                .font(.subheadline)
                                .ghForeground(GHTheme.muted)

                            HStack {
                                Button("Cancel") {
                                    logWithTimestamp("[UploadView] Delete confirm cancelled")
                                    showDeleteConfirm = false
                                }
                                .buttonStyle(GHButtonStyle(color: .gray))

                                Button("Delete") {
                                    guard let entry = pendingDeleteEntry else {
                                        logWithTimestamp("[UploadView] Delete confirm missing pendingDeleteEntry")
                                        showDeleteConfirm = false
                                        return
                                    }
                                    logWithTimestamp("[UploadView] Delete confirm accepted file_id=\(entry.fileId)")
                                    showDeleteConfirm = false
                                    Task { await deleteEntry(entry) }
                                }
                                .buttonStyle(GHButtonStyle(color: .red))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showInvalidTokenPrompt) {
            ZStack {
                GHTheme.bg.ignoresSafeArea()
                VStack {
                    Spacer()
                    GHCard(pad: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Invalid delete token")
                                .font(.headline)
                                .ghForeground(GHTheme.text)
                            Text("The server rejected this delete token. You can remove this entry from the device list or keep it and try again later.")
                                .font(.subheadline)
                                .ghForeground(GHTheme.muted)

                            HStack {
                                Button("Keep") {
                                    logWithTimestamp("[UploadView] Invalid token prompt: keep")
                                    showInvalidTokenPrompt = false
                                }
                                .buttonStyle(GHButtonStyle(color: .gray))

                                Button("Remove from this device") {
                                    guard let entry = invalidTokenEntry else {
                                        logWithTimestamp("[UploadView] Invalid token prompt missing invalidTokenEntry")
                                        showInvalidTokenPrompt = false
                                        return
                                    }
                                    logWithTimestamp("[UploadView] Invalid token prompt: remove file_id=\(entry.fileId)")
                                    showInvalidTokenPrompt = false
                                    removeLocalEntry(entry)
                                }
                                .buttonStyle(GHButtonStyle(color: .red))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    Spacer()
                }
            }
        }
        .alert(isPresented: $showDeleteErrorAlert) {
            Alert(
                title: Text("Delete Failed"),
                message: Text(deleteErrorMessage ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $showResultAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func autoLabel() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "Auto \(df.string(from: eventDate))"
    }

    private func getValidationMessages() -> [String] {
        var messages: [String] = []

        // Check media file
        if fileURL == nil {
            messages.append("Please select a media file")
        } else {
            // Validate file size if file is selected
            if let fileSize = try? fileURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                if Int64(fileSize) > AppConstants.MAX_UPLOAD_SIZE_BYTES {
                    let fileSizeText = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                    let maxSizeText = AppConstants.MAX_UPLOAD_SIZE_FORMATTED
                    messages.append("File too large (\(fileSizeText)) - max allowed: \(maxSizeText)")
                }
            }
        }
                
        // Check organization name
        if orgName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("Band or wedding party name is required")
        }
        
        // Check label (only if autogenerate is not checked)
        if !autogenLabel && label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("Song title or wedding identifier is required")
        }
        
        return messages
    }

    // Reset the temporary cancelled label back to default when user edits anything
    private func resetCancelledStatus() {
        if lastButtonStatus == "Upload Cancelled" {
            lastButtonStatus = nil
        }
    }

    private func doUpload() {
        debugLog = ["button pressed"]
        guard let fileURL else { debugLog.append("no file chosen"); alertTitle = "Missing file"; alertMessage = "Please choose a media file from Photos or Files."; showResultAlert = true; return }
        
        // Add file size to debug log and validate against max upload size
        do {
            let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let fileSizeText = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
            debugLog.append("file size: \(fileSizeText)")
            
            // Validate file size
            if Int64(fileSize) > AppConstants.MAX_UPLOAD_SIZE_BYTES {
                let maxSizeText = AppConstants.MAX_UPLOAD_SIZE_FORMATTED
                debugLog.append("file too large: \(fileSizeText) > \(maxSizeText)")
                alertTitle = "File Too Large"
                alertMessage = "The selected file (\(fileSizeText)) exceeds the maximum allowed size of \(maxSizeText).\n\nPlease select a smaller file or compress the video before uploading."
                // Hard block: clear the selection so the user cannot retry upload without choosing a new file.
                DispatchQueue.main.async {
                    self.fileURL = nil
                    self.loadedFileSize = nil
                    self.isLoadingMedia = false
                    self.photoCopyProgress = nil
                    self.mediaLoadingStartedAt = nil
                    self.cancelPreparingMedia = nil
                }
                showResultAlert = true
                return
            }
        } catch {
            debugLog.append("file size: unknown")
        }
        
        // Use shared session auth + base URL
        guard let base = session.baseURL else { 
            debugLog.append("not logged in")
            alertTitle = "Not Logged In"
            alertMessage = "Please login first to upload."
            showResultAlert = true
            return 
        }
        guard let creds = session.credentials else {
            debugLog.append("missing credentials in session")
            alertTitle = "Missing Credentials"
            alertMessage = "Please login again to provide upload credentials."
            showResultAlert = true
            return
        }
        let payload = UploadPayload(
            fileURL: fileURL,
            eventDate: eventDate,
            orgName: orgName,
            eventType: eventType,
            label: label.isEmpty ? nil : label,
            participants: nil, keywords: nil, location: nil, rating: nil, notes: nil
        )
        // Build client using the provided server credentials
        let client = UploadClient(baseURL: base, basicAuth: (creds.user, creds.pass), useBackgroundSession: false, allowInsecure: session.allowInsecureTLS)
        currentUploadClient = client  // Store reference for cancellation
        isUploading = true
        isCancelling = false
        lastButtonStatus = nil
        lastProgressBucket = 0  // Reset progress tracking for new upload
        uploadTask = Task {
            defer {
                isUploading = false
                isCancelling = false  // Always reset cancelling state when task ends
                loadedFileSize = nil  // Clear file size display after upload completes/cancels
                currentUploadClient = nil  // Clear client reference
                uploadProgress = nil  // Clear upload progress
            }
            do {
                debugLog.append("contacting server \(base.absoluteString)")
                // Pre-log the exact request URL to place progress after this line
                let apiURL = base
                    .appendingPathComponent("api")
                    .appendingPathComponent("uploads.php")
                var comps = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
                comps?.queryItems = [URLQueryItem(name: "ui", value: "json")]
                if let u = comps?.url { debugLog.append("url=\(u.absoluteString)") }
                
                // Show initial progress to let user know progress tracking is active
                debugLog.append("0%..")

                let (status, data, requestURL) = try await client.uploadWithMultipartInputStream(payload, progress: { completed, total in
                    // Special case: -1, -1 means Layer 1 assembly in progress (show dots)
                    if completed == -1 && total == -1 {
                        DispatchQueue.main.async {
                            debugLog.append(".")
                        }
                        return
                    }
                    
                    guard total > 0 else { 
                        logWithTimestamp("⚠️ Progress callback: total is 0")
                        return 
                    }
                    let percent = Int((Double(completed) / Double(total)) * 100.0)
                    let fraction = Double(completed) / Double(total)  // Calculate fraction for progress view
                    let bucket = (percent / 2) * 2  // 2% increments for better feedback on slow connections
                    logWithTimestamp("📈 UploadView Progress: \(completed)/\(total) bytes = \(percent)%, bucket=\(bucket), lastBucket=\(lastProgressBucket)")
                    DispatchQueue.main.async {
                        // Make the bucket dedupe check atomic on the main thread to avoid duplicate entries
                        // when progress callbacks arrive concurrently.
                        if bucket >= 2 && bucket > lastProgressBucket {  // Start at 2%
                            lastProgressBucket = bucket
                            self.uploadProgress = fraction  // Update upload progress state
                            debugLog.append("\(bucket)%..")
                            logWithTimestamp("✅ Added progress to debug log: \(bucket)%")
                        }
                    }
                })
                debugLog.append("payload=org=\(orgName), type=\(eventType), label=\(label.isEmpty ? "(nil)" : label)")
                debugLog.append("upload finished [\(status)]")
                let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"

                let extractJSONCandidate: (String) -> String? = { text in
                    // Prefer extracting JSON from <pre>...</pre> when server wraps JSON in HTML.
                    if let preRange = text.range(of: "<pre", options: .caseInsensitive) {
                        let tail = text[preRange.lowerBound...]
                        if let gt = tail.firstIndex(of: ">") {
                            let after = tail.index(after: gt)
                            let rest = String(tail[after...])
                            if let endPreRange = rest.range(of: "</pre>", options: .caseInsensitive) {
                                let inner = String(rest[..<endPreRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if let start = inner.firstIndex(of: "{"), let end = inner.lastIndex(of: "}"), start <= end {
                                    logWithTimestamp("[UploadView] Extracted JSON from <pre> block")
                                    return String(inner[start...end])
                                }
                            }
                        }
                    }

                    // If the HTML contains CSS (e.g. style blocks), naive "first { ... }" matching will
                    // often capture CSS braces, not JSON. Anchor extraction around "id" or "delete_token".
                    let anchorKeys = ["\"delete_token\"", "\"id\""]
                    let lower = text
                    var anchorIndex: String.Index? = nil
                    for k in anchorKeys {
                        if let r = lower.range(of: k, options: .caseInsensitive) {
                            anchorIndex = r.lowerBound
                            break
                        }
                    }

                    guard let a = anchorIndex else {
                        logWithTimestamp("[UploadView] No JSON anchor (id/delete_token) found in finalize body")
                        return nil
                    }

                    // Walk backwards to a '{' and then brace-match forward to a full JSON object.
                    var startIdx = a
                    while startIdx > lower.startIndex {
                        let prev = lower.index(before: startIdx)
                        if lower[prev] == "{" {
                            startIdx = prev
                            break
                        }
                        startIdx = prev
                    }
                    if lower[startIdx] != "{" {
                        logWithTimestamp("[UploadView] Could not find '{' before JSON anchor")
                        return nil
                    }

                    let chars = Array(lower[startIdx...])
                    var depth = 0
                    var inString = false
                    var escape = false
                    for j in 0..<chars.count {
                        let c = chars[j]
                        if inString {
                            if escape {
                                escape = false
                            } else if c == "\\" {
                                escape = true
                            } else if c == "\"" {
                                inString = false
                            }
                            continue
                        }

                        if c == "\"" {
                            inString = true
                            continue
                        }
                        if c == "{" {
                            depth += 1
                        } else if c == "}" {
                            depth -= 1
                            if depth == 0 {
                                let candidate = String(chars[0...j])
                                logWithTimestamp("[UploadView] Extracted JSON via anchor brace-match (len=\(candidate.count))")
                                return candidate
                            }
                        }
                    }

                    logWithTimestamp("[UploadView] Anchor brace-match did not find a balanced JSON object")
                    return nil
                }

                switch status {
                case 200, 201:
                    alertTitle = "Success"
                    alertMessage = "Upload succeeded."
                    let baseURL = base.appendingPathComponent("db").appendingPathComponent("database.php")
                    // Add cache-busting timestamp
                    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
                    components?.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
                    let url = components?.url ?? baseURL
                    successURL = url
                    failureCount = 0

                    let decodeAndPersist: (FinalizeResponse) -> Void = { resp in
                        if let host = session.baseURL?.host, !host.isEmpty {
                            debugLog.append("finalize decoded: id=\(resp.id), host=\(host)")
                            let token = resp.deleteToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            if token.isEmpty {
                                let msg = "File uploaded successfully, but no delete token was returned by the server. This usually happens when the server dedupes the upload (same file content/sha256 as a previous upload). Deduped uploads can't be deleted from the server via the app. Contact contactgighive@gmail.com to request a manual deletion. You will need to submit the following information: file_id, checksum_sha256, event_date, org_name, event_type, label or file name.\n\n" +
                                "file_id: \(resp.id)\n" +
                                "checksum_sha256: \(resp.checksumSha256 ?? "")\n" +
                                "event_date: \(resp.eventDate ?? "")\n" +
                                "org_name: \(resp.orgName ?? "")\n" +
                                "event_type: \(resp.eventType ?? "")\n" +
                                "label: \(resp.label ?? "")\n" +
                                "file_name: \(resp.fileName ?? "")"
                                alertMessage = msg
                            } else {
                                debugLog.append("finalize delete_token present (len=\(token.count))")
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
                                do {
                                    try UploaderDeleteTokenStore.upsert(host: host, entry: entry)
                                    debugLog.append("saved delete token")
                                    DispatchQueue.main.async {
                                        reloadMyUploadsOnDevice()
                                    }
                                } catch {
                                    debugLog.append("failed to save delete token: \(error.localizedDescription)")
                                }
                            }
                        } else {
                            debugLog.append("missing host for delete token store")
                        }
                    }

                    do {
                        let resp = try JSONDecoder().decode(FinalizeResponse.self, from: data)
                        decodeAndPersist(resp)
                    } catch {
                        logWithTimestamp("[UploadView] Finalize direct JSON decode failed; attempting extraction")

                        let decodeCandidate: (String) -> FinalizeResponse? = { candidate in
                            let trimmedCandidate: String = {
                                if let start = candidate.firstIndex(of: "{"), let end = candidate.lastIndex(of: "}"), start <= end {
                                    return String(candidate[start...end])
                                }
                                return candidate
                            }()

                            let htmlDecoded: String = {
                                // Some environments return JSON HTML-escaped inside <pre>.
                                guard trimmedCandidate.contains("&") else { return trimmedCandidate }
                                if let data = trimmedCandidate.data(using: .utf8) {
                                    let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                                        .documentType: NSAttributedString.DocumentType.html,
                                        .characterEncoding: String.Encoding.utf8.rawValue
                                    ]
                                    if let attributed = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) {
                                        return attributed.string
                                    }
                                }
                                return trimmedCandidate
                            }()

                            let finalText = htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines)
                            let prefix = String(finalText.prefix(200))
                            logWithTimestamp("[UploadView] Finalize extracted candidate len=\(finalText.count); prefix=\(prefix)")

                            guard let jsonData = finalText.data(using: .utf8) else { return nil }
                            do {
                                return try JSONDecoder().decode(FinalizeResponse.self, from: jsonData)
                            } catch {
                                logWithTimestamp("[UploadView] Finalize candidate decode error: \(error)")
                                return nil
                            }
                        }

                        if let candidate = extractJSONCandidate(bodyText), let resp = decodeCandidate(candidate) {
                            debugLog.append("finalize JSON decode succeeded after extraction")
                            decodeAndPersist(resp)
                        } else {
                            let snippet = String(bodyText.prefix(240))
                            debugLog.append("finalize JSON decode failed; body prefix=\(snippet)")
                            logWithTimestamp("[UploadView] Finalize JSON extraction/decode failed; body prefix=\(snippet)")
                            logWithTimestamp("[UploadView] Finalize direct decode error: \(error)")
                        }
                    }

                    // Prepend success message to debug log
                    debugLog.insert("UPLOAD SUCCESSFUL!", at: 0)
                    debugLog.append("db link=\(url.absoluteString)")
                    // Clear fields after success (update UI on main thread)
                    DispatchQueue.main.async {
                        self.fileURL = nil
                        self.label = ""
                        // Hide keyboard after successful upload
                        self.hideKeyboard()
                    }
                    debugLog.append("cleared file and label")
                    debugLog.append("\n\nYou are free to upload another file.")
                case 401, 403:
                    alertTitle = status == 401 ? "Unauthorized" : "Forbidden"
                    alertMessage = status == 401 
                        ? "401 Unauthorized. You do not have permission to upload to this server. Please re-login as an admin or uploader."
                        : "403 Forbidden. You do not have permission to upload to this server. Please re-login as an admin or uploader."
                    failureCount += 1
                case 413:
                    alertTitle = "File Too Large"
                    alertMessage = "413 Payload Too Large.\n\nYour file exceeds the maximum allowed size of \(AppConstants.MAX_UPLOAD_SIZE_FORMATTED).\n\nPlease select a smaller file or compress the video before uploading."
                    failureCount += 1
                case 400:
                    alertTitle = "Bad Request"
                    alertMessage = bodyText
                    failureCount += 1
                case 409:
                    alertTitle = "Duplicate Upload"
                    if let candidate = extractJSONCandidate(bodyText),
                       let jsonData = candidate.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: jsonData, options: []),
                       let dict = obj as? [String: Any] {
                        let existingId = dict["existing_file_id"]
                        let checksum = dict["checksum_sha256"]
                        let msg = dict["message"] as? String
                        var lines: [String] = []
                        if let msg, !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(msg) }
                        if let existingId { lines.append("existing_file_id: \(existingId)") }
                        if let checksum { lines.append("checksum_sha256: \(checksum)") }
                        alertMessage = lines.isEmpty ? "A file with the same content (SHA256) already exists on the server. Upload rejected to prevent duplicates." : lines.joined(separator: "\n")
                    } else {
                        alertMessage = "A file with the same content (SHA256) already exists on the server. Upload rejected to prevent duplicates."
                    }
                    failureCount += 1
                default:
                    alertTitle = "HTTP \(status)"
                    alertMessage = bodyText
                    failureCount += 1
                }
            } catch is CancellationError {
                // Task was cancelled by user
                debugLog.append("cancelled")
                lastButtonStatus = "Upload Cancelled"
                // Clear selected file after cancellation
                DispatchQueue.main.async {
                    self.fileURL = nil
                }
                // Reset back to default after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if lastButtonStatus == "Upload Cancelled" {
                        lastButtonStatus = nil
                    }
                }
                return
            } catch {
                // Map URLError.cancelled to a user-initiated cancel as well
                if let urlErr = error as? URLError, urlErr.code == .cancelled {
                    debugLog.append("cancelled")
                    lastButtonStatus = "Upload Cancelled"
                    // Clear selected file after cancellation
                    DispatchQueue.main.async {
                        self.fileURL = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if lastButtonStatus == "Upload Cancelled" {
                            lastButtonStatus = nil
                        }
                    }
                    return
                }
                debugLog.append("error: \(error.localizedDescription)")
                alertTitle = "Error"
                alertMessage = error.localizedDescription
                failureCount += 1
            }
            // Hide keyboard before showing alert to prevent it from reappearing
            hideKeyboard()
            // Small delay to ensure keyboard is fully dismissed before alert appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showResultAlert = true
            }
            onUpload(payload)
        }
    }

    private func makeSupportEmailLink() -> URL? {
        let to = "admin@gighive.local" // TODO: replace with real admin address
        let subject = "GigHive iOS Upload Help"
        let body = (debugLog + ["server=\(serverURLString)", "user=\(username)"]).joined(separator: "\n")
        let enc: (String) -> String = { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }
        return URL(string: "mailto:\(to)?subject=\(enc(subject))&body=\(enc(body))")
    }

    private func hideKeyboard() {
        // iOS 14 safe keyboard dismissal
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func removeLocalEntry(_ entry: UploadedFileTokenEntry) {
        guard let host = session.baseURL?.host, !host.isEmpty else {
            reloadMyUploadsOnDevice()
            return
        }
        do {
            try UploaderDeleteTokenStore.remove(host: host, fileId: entry.fileId)
        } catch {
        }
        reloadMyUploadsOnDevice()
    }

    private func deleteEntry(_ entry: UploadedFileTokenEntry) async {
        logWithTimestamp("[UploadView] deleteEntry start file_id=\(entry.fileId)")
        guard let baseURL = session.baseURL else {
            logWithTimestamp("[UploadView] deleteEntry abort: missing baseURL")
            deleteErrorMessage = "Missing base URL"
            showDeleteErrorAlert = true
            return
        }
        guard let creds = session.credentials else {
            logWithTimestamp("[UploadView] deleteEntry abort: missing credentials")
            deleteErrorMessage = "Missing credentials"
            showDeleteErrorAlert = true
            return
        }
        guard let host = baseURL.host, !host.isEmpty else {
            logWithTimestamp("[UploadView] deleteEntry abort: missing host")
            deleteErrorMessage = "Missing host"
            showDeleteErrorAlert = true
            return
        }

        logWithTimestamp("[UploadView] deleteEntry calling API host=\(host) user=\(creds.user)")

        do {
            let client = DatabaseAPIClient(baseURL: baseURL, basicAuth: creds, allowInsecure: session.allowInsecureTLS)
            let resp = try await client.deleteMediaFile(fileId: entry.fileId, deleteToken: entry.deleteToken)
            logWithTimestamp("[UploadView] deleteEntry API response success=\(resp.success) deleted=\(resp.deletedCount) errors=\(resp.errorCount)")
            if resp.deletedCount == 1 {
                removeLocalEntry(entry)
            } else {
                deleteErrorMessage = "Delete did not remove the file (deleted_count=\(resp.deletedCount), error_count=\(resp.errorCount))"
                showDeleteErrorAlert = true
            }
        } catch {
            logWithTimestamp("[UploadView] deleteEntry error: \(error)")
            if let dbErr = error as? DatabaseError {
                switch dbErr {
                case .httpError(let code) where code == 403:
                    invalidTokenEntry = entry
                    showInvalidTokenPrompt = true
                default:
                    deleteErrorMessage = dbErr.localizedDescription
                    showDeleteErrorAlert = true
                }
            } else {
                deleteErrorMessage = error.localizedDescription
                showDeleteErrorAlert = true
            }
        }
    }

    private func reloadMyUploadsOnDevice() {
        guard let host = session.baseURL?.host, !host.isEmpty else {
            myUploadsOnDevice = []
            return
        }
        do {
            myUploadsOnDevice = try UploaderDeleteTokenStore.load(host: host)
        } catch {
            myUploadsOnDevice = []
        }
    }
}
