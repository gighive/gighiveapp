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
    @EnvironmentObject var uploadState: UploadStateStore
    // SERVER
    @AppStorage("gh_server_url") private var serverURLString: String = "https://gighive" // editable by user
    @AppStorage("gh_basic_user") private var username: String = ""
    @AppStorage("gh_basic_pass") private var password: String = ""
    @AppStorage("gh_eventType_default") private var storedEventType: String = "band"

    @State private var showPhotosPicker = false
    @State private var showFilesPicker = false
    @State private var allowInsecureTLS = false
    @State private var pendingFileSizeError: FileSizeError? = nil
    @State private var pendingLoadError: String? = nil
    @State private var myUploadsOnDevice: [UploadedFileTokenEntry] = []
    @State private var pendingDeleteEntry: UploadedFileTokenEntry? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var invalidTokenEntry: UploadedFileTokenEntry? = nil
    @State private var showInvalidTokenPrompt: Bool = false
    @State private var deleteErrorMessage: String? = nil
    @State private var showDeleteErrorAlert: Bool = false

    let onUpload: (UploadPayload) -> Void
    @Environment(\.openURL) private var openURL

    private var fileURL: URL? {
        get { uploadState.fileURL }
        nonmutating set { uploadState.fileURL = newValue }
    }

    private var eventDate: Date {
        get { uploadState.eventDate }
        nonmutating set { uploadState.eventDate = newValue }
    }

    private var orgName: String {
        get { uploadState.orgName }
        nonmutating set { uploadState.orgName = newValue }
    }

    private var eventType: String {
        get { uploadState.eventType }
        nonmutating set { uploadState.eventType = newValue }
    }

    private var label: String {
        get { uploadState.label }
        nonmutating set { uploadState.label = newValue }
    }

    private var autogenLabel: Bool {
        get { uploadState.autogenLabel }
        nonmutating set { uploadState.autogenLabel = newValue }
    }

    private var isUploading: Bool {
        get { uploadState.isUploading }
        nonmutating set { uploadState.isUploading = newValue }
    }

    private var isCancelling: Bool {
        get { uploadState.isCancelling }
        nonmutating set { uploadState.isCancelling = newValue }
    }

    private var showResultAlert: Bool {
        get { uploadState.showResultAlert }
        nonmutating set { uploadState.showResultAlert = newValue }
    }

    private var alertTitle: String {
        get { uploadState.alertTitle }
        nonmutating set { uploadState.alertTitle = newValue }
    }

    private var alertMessage: String {
        get { uploadState.alertMessage }
        nonmutating set { uploadState.alertMessage = newValue }
    }

    private var debugLog: [String] {
        get { uploadState.debugLog }
        nonmutating set { uploadState.debugLog = newValue }
    }

    private var successURL: URL? {
        get { uploadState.successURL }
        nonmutating set { uploadState.successURL = newValue }
    }

    private var failureCount: Int {
        get { uploadState.failureCount }
        nonmutating set { uploadState.failureCount = newValue }
    }

    private var lastButtonStatus: String? {
        get { uploadState.lastButtonStatus }
        nonmutating set { uploadState.lastButtonStatus = newValue }
    }

    private var isLoadingMedia: Bool {
        get { uploadState.isLoadingMedia }
        nonmutating set { uploadState.isLoadingMedia = newValue }
    }

    private var loadedFileSize: String? {
        get { uploadState.loadedFileSize }
        nonmutating set { uploadState.loadedFileSize = newValue }
    }

    private var mediaLoadingStartedAt: Date? {
        get { uploadState.mediaLoadingStartedAt }
        nonmutating set { uploadState.mediaLoadingStartedAt = newValue }
    }

    private var lastProgressBucket: Int {
        get { uploadState.lastProgressBucket }
        nonmutating set { uploadState.lastProgressBucket = newValue }
    }

    private var photoCopyProgress: Double? {
        get { uploadState.photoCopyProgress }
        nonmutating set { uploadState.photoCopyProgress = newValue }
    }

    private var uploadProgress: Double? {
        get { uploadState.uploadProgress }
        nonmutating set { uploadState.uploadProgress = newValue }
    }

    private var uploadTask: Task<Void, Never>? {
        get { uploadState.uploadTask }
        nonmutating set { uploadState.uploadTask = newValue }
    }

    private var currentUploadClient: UploadClient? {
        get { uploadState.currentUploadClient }
        nonmutating set { uploadState.currentUploadClient = newValue }
    }

    private var cancelPreparingMedia: (() -> Void)? {
        get { uploadState.cancelPreparingMedia }
        nonmutating set { uploadState.cancelPreparingMedia = newValue }
    }

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
                if let displayUser = session.credential?.displayUser {
                    Text("User is logged into \(session.baseURL?.absoluteString ?? "<unknown>") as \(displayUser)")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }

                GHCard(pad: 8) {
                    VStack(alignment: .leading, spacing: 6) {

                        Text("Max upload size: \(AppConstants.MAX_UPLOAD_SIZE_FORMATTED)")
                            .font(.caption2)
                            .ghForeground(GHTheme.muted)

                        Text("Tip: Videos stored in iCloud must download and export before uploading. For a 12-minute 4K video this may take 5–10 minutes. Verify large video sizes before selecting.")
                            .font(.caption2)
                            .foregroundColor(.orange)

                        LabeledField("Media file (audio/video) *") {
                            Menu {
                                Button("From Files", action: { 
                                    loadedFileSize = nil  // Clear previous file size
                                    isLoadingMedia = true  // Show loading immediately when dropdown option is touched
                                    showFilesPicker = true 
                                })
                                .accessibilityIdentifier("upload_from_files_button")
                                Button("From Photos", action: { 
                                    loadedFileSize = nil  // Clear previous file size
                                    // Don't set isLoadingMedia here - it will be set when copy starts via onCopyStarted callback
                                    showPhotosPicker = true 
                                })
                                .accessibilityIdentifier("upload_from_photos_button")
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
                                        Text("Converting video to H.264 format for compatibility. This may take a few minutes for large videos.\n\nIf you wish all your videos to be in H.264 format going forward, change this setting on the iPhone: Settings → Camera → Formats → \"Most Compatible\"")
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
                            DatePicker("", selection: Binding(get: { eventDate }, set: { eventDate = $0 }), displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(CompactDatePickerStyle())
                                .ghForeground(GHTheme.text)
                                .environment(\.colorScheme, .dark)
                        }

                        LabeledField("Band or wedding party name *") {
                            NoAccessoryTextField(
                                text: Binding(get: { orgName }, set: { orgName = $0 }),
                                placeholder: "",
                                keyboardType: .default,
                                autocapitalizationType: .words,
                                autocorrectionType: .no,
                                accessibilityIdentifier: "upload_org_name_field"
                            )
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .ghBackgroundMaterial()
                            .cornerRadius(6)
                        }

                        LabeledField("Event type *") {
                            Picker("", selection: Binding(get: { eventType }, set: { eventType = $0 })) {
                                Text("band").tag("band")
                                Text("wedding").tag("wedding")
                            }
                            .pickerStyle(.segmented)
                        }

                        LabeledField("Song title or wedding table / identifier *") {
                            NoAccessoryTextField(
                                text: Binding(get: { label }, set: { label = $0 }),
                                placeholder: "",
                                keyboardType: .default,
                                autocapitalizationType: .none,
                                autocorrectionType: .no,
                                accessibilityIdentifier: "upload_song_title_field"
                            )
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .ghBackgroundMaterial()
                            .cornerRadius(6)
                        }

                        Toggle(isOn: Binding(get: { autogenLabel }, set: { autogenLabel = $0 })) {
                            GHLabel(text: "Autogenerate label?")
                        }
                        .ghTint(GHTheme.accent)

                        if autogenLabel {
                            Text("If checked, the label will be set to \"Auto YYYY-MM-DD\" based on the Event date.")
                                .ghForeground(GHTheme.muted)
                        }

                        Button(isCancelling ? "Cancelling…" : (isUploading ? "Uploading…" : (isLoadingMedia ? "Cancel" : (lastButtonStatus ?? "Upload"))), action: { // upload_submit_button
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
                            .accessibilityIdentifier("upload_submit_button")

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
                                    Text("Do not navigate away from this page or your upload will be cancelled.")
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
        .dismissKeyboardOnScroll()
        .ghFullScreenBackground(GHTheme.bg)
        .sheet(isPresented: $showPhotosPicker) {
            PHPickerView(selectionHandler: { url in
                onMain {
                    debugLog = []

                    if let url = url {
                        logWithTimestamp("📸 [PHPicker] File selected, setting fileURL")
                        self.loadedFileSize = nil
                        self.fileURL = url
                        self.showPhotosPicker = false
                        self.cancelPreparingMedia = nil
                        debugLog.append("file selected from Photos")
                    } else {
                        self.showPhotosPicker = false
                        self.fileURL = nil
                        self.loadedFileSize = nil
                        self.isLoadingMedia = false
                        self.cancelPreparingMedia = nil
                        debugLog.append("photos canceled")
                    }
                }
            }, onFileTooLarge: { fileSize, maxSize in
                logWithTimestamp("🚫 [PHPicker] onFileTooLarge callback fired: \(fileSize) > \(maxSize)")
                onMain {
                    debugLog.append("file rejected: \(fileSize) > \(maxSize)")
                    self.showPhotosPicker = false
                }
                logWithTimestamp("🚫 [PHPicker] Dismissed picker sheet")
                // Delay setting error until after picker dismisses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    logWithTimestamp("🚫 [PHPicker] Setting pendingFileSizeError state")
                    self.pendingFileSizeError = FileSizeError(fileSize: fileSize, maxSize: maxSize)
                    logWithTimestamp("🚫 [PHPicker] pendingFileSizeError set to: \(String(describing: self.pendingFileSizeError))")
                }
            }, onCopyStarted: {
                logWithTimestamp("📸 [PHPicker] onCopyStarted - showing progress indicator")
                onMain {
                    self.isLoadingMedia = true
                    self.mediaLoadingStartedAt = Date()
                    self.loadedFileSize = nil
                    self.photoCopyProgress = nil
                    debugLog.append("copying file from Photos...")
                }
            }, onCopyProgress: { progress in
                onMain {
                    self.photoCopyProgress = progress
                }
            }, onCopyCancelAvailable: { cancel in
                if cancel == nil {
                    logWithTimestamp("🧹 [UploadView] Received nil cancel hook (clearing)")
                } else {
                    logWithTimestamp("🧷 [UploadView] Received cancel hook (installing)")
                }
                onMain {
                    self.cancelPreparingMedia = cancel
                }
            }, onLoadError: { message in
                logWithTimestamp("⚠️ [PHPicker] onLoadError: \(message)")
                onMain {
                    self.showPhotosPicker = false
                    self.isLoadingMedia = false
                    self.photoCopyProgress = nil
                    self.cancelPreparingMedia = nil
                    self.pendingLoadError = message
                }
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
                    onMain {
                        debugLog = []
                    }

                    if let url = url {
                        let startedAt = Date()
                        onMain {
                            self.mediaLoadingStartedAt = startedAt
                            self.isLoadingMedia = true
                            self.loadedFileSize = nil
                            self.fileURL = url
                            self.showFilesPicker = false
                            debugLog.append("reading file metadata...")
                        }

                        DispatchQueue.global(qos: .userInitiated).async {
                            let minVisible: TimeInterval = 1.0
                            let sizeText: String = {
                                do {
                                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                                    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                                } catch {
                                    return "unknown"
                                }
                            }()
                            let elapsed = Date().timeIntervalSince(startedAt)
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
                        onMain {
                            self.showFilesPicker = false
                            self.fileURL = nil
                            self.loadedFileSize = nil
                            self.isLoadingMedia = false
                            debugLog.append("files canceled")
                        }
                    }
                },
                onFileTooLarge: { fileSize, maxSize in
                    logWithTimestamp("🚫 [DocumentPicker] onFileTooLarge callback fired: \(fileSize) > \(maxSize)")
                    onMain {
                        debugLog.append("file rejected: \(fileSize) > \(maxSize)")
                        self.showFilesPicker = false
                    }
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
                let startedAt = self.mediaLoadingStartedAt ?? Date()
                
                // Compute file size on background thread
                DispatchQueue.global(qos: .userInitiated).async {
                    let minVisible: TimeInterval = 1.0
                    let sizeText: String = {
                        do {
                            let bytes = try newURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                        } catch {
                            return "unknown"
                        }
                    }()
                    let elapsed = Date().timeIntervalSince(startedAt)
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
        .onChange(of: pendingLoadError) { message in
            guard let message = message else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.alertTitle = "Video Load Failed"
                self.alertMessage = message
                self.showResultAlert = true
                self.pendingLoadError = nil
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
            // UI-test hook: pre-seed the file picker with a filename found in the app's
            // Documents directory. Usage: --uitest-upload-file <filename.mp4>
            // The file must be copied into the app sandbox before the test runs.
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "--uitest-upload-file"),
               args.indices.contains(idx + 1) {
                let name = args[idx + 1]
                let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                if let url = docsURL?.appendingPathComponent(name),
                   FileManager.default.fileExists(atPath: url.path) {
                    fileURL = url
                    logWithTimestamp("[UploadView] UI-test pre-seeded fileURL=\(url.lastPathComponent)")
                } else {
                    logWithTimestamp("[UploadView] UI-test --uitest-upload-file: file '\(name)' not found in Documents")
                }
            }
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
        .alert(isPresented: Binding(get: { showResultAlert }, set: { showResultAlert = $0 })) {
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

    private func onMain(_ updates: @escaping () -> Void) {
        if Thread.isMainThread {
            updates()
        } else {
            DispatchQueue.main.async(execute: updates)
        }
    }

    private var unsupportedFormatMessage: String {
        "WebM video is not supported for iPhone playback.\n\nPlease convert the file to MP4 (H.264 video with AAC audio) and upload that version instead."
    }

    private func isUnsupportedUploadFormat(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "webm"
    }

    private func clearSelectedFile() {
        fileURL = nil
        loadedFileSize = nil
        isLoadingMedia = false
        photoCopyProgress = nil
        mediaLoadingStartedAt = nil
        cancelPreparingMedia = nil
    }

    private func getValidationMessages() -> [String] {
        var messages: [String] = []

        // Check media file
        if fileURL == nil {
            messages.append("Please select a media file")
        } else {
            if let fileURL, isUnsupportedUploadFormat(fileURL) {
                messages.append("WebM video is not supported on iPhone. Please upload MP4 instead")
            }
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

        if isUnsupportedUploadFormat(fileURL) {
            debugLog.append("unsupported format: .webm")
            alertTitle = "Unsupported Video Format"
            alertMessage = unsupportedFormatMessage
            DispatchQueue.main.async {
                self.clearSelectedFile()
            }
            showResultAlert = true
            return
        }
        
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
                DispatchQueue.main.async {
                    self.clearSelectedFile()
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
        guard session.credential != nil else {
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
        let client = UploadClient(baseURL: base, sessionCredential: session.credential, useBackgroundSession: false, allowInsecure: session.allowInsecureTLS)
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

                let (status, data, _) = try await client.uploadWithMultipartInputStream(payload, progress: { completed, total in
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
                    alertMessage = "413 Payload Too Large.\n\nThis upload exceeds Cloudflare's single-request limit of \(AppConstants.CLOUDFLARE_SINGLE_REQUEST_LIMIT_FORMATTED).\n\nGigHive's maximum allowed file size is \(AppConstants.MAX_UPLOAD_SIZE_FORMATTED), but uploads larger than \(AppConstants.CLOUDFLARE_SINGLE_REQUEST_LIMIT_FORMATTED) cannot be sent through this endpoint.\n\nPlease select a smaller file or compress the video before uploading."
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
        guard session.credential != nil else {
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

        logWithTimestamp("[UploadView] deleteEntry calling API host=\(host) user=\(session.credential?.displayUser ?? "<unknown>")")

        do {
            let client = DatabaseAPIClient(baseURL: baseURL, credential: session.credential, allowInsecure: session.allowInsecureTLS)
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
