import SwiftUI
import UniformTypeIdentifiers

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
    @State private var loadedFileSize: String? = nil
    // Ensure loading text is visible for at least a minimum duration
    @State private var mediaLoadingStartedAt: Date? = nil
    @State private var lastProgressBucket: Int = 0
    @State private var pendingFileSizeError: FileSizeError? = nil
    @State private var photoCopyProgress: Double? = nil  // 0.0 to 1.0 for Photos copy progress

    let onUpload: (UploadPayload) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image("beelogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: UIFont.preferredFont(forTextStyle: .title2).pointSize + 2)
                    Text("Gighive Upload")
                        .font(.title3).bold()
                        .ghForeground(GHTheme.text)
                }

                // SERVER CARD
                GHCard(pad: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        GHLabel(text: "SERVER")

                        LabeledField("") {
                            NoAccessoryTextField(
                                text: $serverURLString,
                                placeholder: "https://example.com",
                                keyboardType: .URL,
                                autocapitalizationType: .none,
                                autocorrectionType: .no
                            )
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .ghBackgroundMaterial()
                            .cornerRadius(6)
                        }

                        LabeledField("Username *") {
                            NoAccessoryTextField(
                                text: $username,
                                placeholder: "admin/uploader username",
                                keyboardType: .default,
                                autocapitalizationType: .none,
                                autocorrectionType: .no
                            )
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .ghBackgroundMaterial()
                            .cornerRadius(6)
                        }

                        LabeledField("Password *") {
                            NoAccessorySecureField(
                                text: $password,
                                placeholder: "password",
                                keyboardType: .default,
                                autocapitalizationType: .none,
                                autocorrectionType: .no
                            )
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .ghBackgroundMaterial()
                            .cornerRadius(6)
                        }

                        // Default event type removed from SERVER: we persist the META selection instead.
                    }
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
                                            Text("Copying from Photos... \(Int(progress * 100))%")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                                .bold()
                                        } else {
                                            Text("Preparing video from Photos...")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                                .bold()
                                        }
                                        Text("This may take a few minutes for large videos. iOS requires copying the file for security.")
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

                        Button(isCancelling ? "Cancelling…" : (isUploading ? "Uploading…" : (lastButtonStatus ?? "Upload")), action: {
                            if isUploading {
                                // Second press: cancel
                                isCancelling = true
                                debugLog.append("cancelling…")
                                uploadTask?.cancel()
                                
                                // Also cancel the underlying network upload task
                                currentUploadClient?.cancelCurrentUpload()
                            } else {
                                doUpload()
                            }
                        })
                            .buttonStyle(GHButtonStyle(color: lastButtonStatus == "Upload Cancelled" ? .red : GHTheme.accent))
                            .disabled((!isUploading) && (isLoadingMedia || fileURL == nil || (label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
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

                        if !debugLog.isEmpty {
                            Text(debugLog.joined(separator: " → "))
                                .font(.caption2)
                                .foregroundColor(.red)
                                .padding(.top, 2)
                        }


                        if let url = successURL {
                            Button(action: {
                                openURL(url)
                            }) {
                                Text("View in Database")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(GHButtonStyle(color: .green))
                            .padding(.top, 8)
                        }

                        Toggle(isOn: $allowInsecureTLS) {
                            Text("Disable Certificate Checking").font(.caption2).ghForeground(GHTheme.muted)
                        }
                        .ghTint(GHTheme.accent)
                        .padding(.top, 4)

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
                    print("📸 [PHPicker] File selected, setting fileURL")
                    self.loadedFileSize = nil
                    self.fileURL = url
                    self.showPhotosPicker = false
                    debugLog.append("file selected from Photos")
                } else {
                    // User cancelled
                    self.showPhotosPicker = false
                    self.fileURL = nil
                    self.loadedFileSize = nil
                    self.isLoadingMedia = false
                    debugLog.append("photos canceled")
                }
            }, onFileTooLarge: { fileSize, maxSize in
                // Dismiss picker first, then set error state
                print("🚫 [PHPicker] onFileTooLarge callback fired: \(fileSize) > \(maxSize)")
                debugLog.append("file rejected: \(fileSize) > \(maxSize)")
                self.showPhotosPicker = false
                print("🚫 [PHPicker] Dismissed picker sheet")
                // Delay setting error until after picker dismisses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("🚫 [PHPicker] Setting pendingFileSizeError state")
                    self.pendingFileSizeError = FileSizeError(fileSize: fileSize, maxSize: maxSize)
                    print("🚫 [PHPicker] pendingFileSizeError set to: \(String(describing: self.pendingFileSizeError))")
                }
            }, onCopyStarted: {
                // File copy from Photos has started - show progress immediately
                print("📸 [PHPicker] onCopyStarted - showing progress indicator")
                self.isLoadingMedia = true
                self.mediaLoadingStartedAt = Date()
                self.loadedFileSize = nil
                self.photoCopyProgress = nil
                debugLog.append("copying file from Photos...")
            }, onCopyProgress: { progress in
                // Update progress during copy
                self.photoCopyProgress = progress
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
                    print("🚫 [DocumentPicker] onFileTooLarge callback fired: \(fileSize) > \(maxSize)")
                    debugLog.append("file rejected: \(fileSize) > \(maxSize)")
                    self.showFilesPicker = false
                    print("🚫 [DocumentPicker] Dismissed picker sheet")
                    // Delay setting error until after picker dismisses
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        print("🚫 [DocumentPicker] Setting pendingFileSizeError state")
                        self.pendingFileSizeError = FileSizeError(fileSize: fileSize, maxSize: maxSize)
                        print("🚫 [DocumentPicker] pendingFileSizeError set to: \(String(describing: self.pendingFileSizeError))")
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
                print("📸 [onChange(fileURL)] File cleared")
                return
            }
            
            // Only show loading if we don't have a file size yet
            // (Files picker is fast and doesn't need progress)
            guard loadedFileSize == nil else {
                print("📸 [onChange(fileURL)] File size already loaded, skipping progress")
                return
            }
            
            print("📸 [onChange(fileURL)] New file selected, starting progress after delay")
            // Small delay to ensure picker sheet is fully dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("📸 [onChange(fileURL)] Showing loading indicator")
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
                    print("📸 [Background] File size calculated: \(sizeText), elapsed: \(elapsed)s, remaining: \(remaining)s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                        print("📸 [Background] Updating UI with file size")
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
            print("🔔 [onChange] pendingFileSizeError changed to: \(String(describing: error))")
            guard let error = error else { 
                print("🔔 [onChange] Error is nil, returning")
                return 
            }
            print("🔔 [onChange] Scheduling alert with 0.6s delay")
            let fileSize = error.fileSize
            let maxSize = error.maxSize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                print("🔔 [onChange] Showing alert now")
                self.alertTitle = "File Too Large"
                self.alertMessage = "The selected file (\(fileSize)) exceeds the maximum allowed size of \(maxSize).\n\nPlease select a smaller file or compress the video before uploading."
                self.showResultAlert = true
                print("🔔 [onChange] showResultAlert set to true")
                self.pendingFileSizeError = nil  // Clear after showing
                print("🔔 [onChange] Cleared pendingFileSizeError")
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
        .onChange(of: serverURLString) { _ in resetCancelledStatus() }
        .onChange(of: username) { _ in resetCancelledStatus() }
        .onChange(of: password) { _ in resetCancelledStatus() }
        .onAppear {
            // Initialize META picker from the last used value
            eventType = storedEventType
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
        
        // Check username
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("Username is required")
        }
        
        // Check password
        if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("Password is required")
        }

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
                showResultAlert = true
                return
            }
        } catch {
            debugLog.append("file size: unknown")
        }
        
        guard let base = URL(string: serverURLString) else { debugLog.append("invalid server url"); alertTitle = "Invalid Server URL"; alertMessage = "Please enter a valid https:// server URL."; showResultAlert = true; return }
        let payload = UploadPayload(
            fileURL: fileURL,
            eventDate: eventDate,
            orgName: orgName,
            eventType: eventType,
            label: label.isEmpty ? nil : label,
            participants: nil, keywords: nil, location: nil, rating: nil, notes: nil
        )
        // Build client using the provided server credentials
        let client = UploadClient(baseURL: base, basicAuth: (username, password), useBackgroundSession: false, allowInsecure: allowInsecureTLS)
        currentUploadClient = client  // Store reference for cancellation
        isUploading = true
        isCancelling = false
        lastButtonStatus = nil
        lastProgressBucket = 0  // Reset progress tracking for new upload
        uploadTask = Task { [serverURLString, orgName, eventType, label] in
            defer { 
                isUploading = false
                isCancelling = false  // Always reset cancelling state when task ends
                loadedFileSize = nil  // Clear file size display after upload completes/cancels
                currentUploadClient = nil  // Clear client reference
            }
            do {
                debugLog.append("contacting server \(serverURLString)")
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
                        print("⚠️ Progress callback: total is 0")
                        return 
                    }
                    let percent = Int((Double(completed) / Double(total)) * 100.0)
                    let bucket = (percent / 5) * 5  // Changed from 10% to 5% increments
                    print("📈 UploadView Progress: \(completed)/\(total) bytes = \(percent)%, bucket=\(bucket), lastBucket=\(lastProgressBucket)")
                    if bucket >= 5 && bucket > lastProgressBucket {  // Changed from 10 to 5
                        DispatchQueue.main.async {
                            lastProgressBucket = bucket
                            debugLog.append("\(bucket)%..")
                            print("✅ Added progress to debug log: \(bucket)%")
                        }
                    }
                })
                debugLog.append("payload=org=\(orgName), type=\(eventType), label=\(label.isEmpty ? "(nil)" : label)")
                debugLog.append("upload finished [\(status)]")
                let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
                switch status {
                case 201:
                    alertTitle = "Success"
                    alertMessage = "Upload succeeded."
                    let baseURL = base.appendingPathComponent("db").appendingPathComponent("database.php")
                    // Add cache-busting timestamp
                    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
                    components?.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
                    let url = components?.url ?? baseURL
                    successURL = url
                    failureCount = 0
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
                case 401:
                    alertTitle = "Unauthorized"
                    alertMessage = "401 Unauthorized. Check Basic Auth username/password."
                    failureCount += 1
                case 413:
                    alertTitle = "File Too Large"
                    alertMessage = "413 Payload Too Large.\n\nYour file exceeds the maximum allowed size of \(AppConstants.MAX_UPLOAD_SIZE_FORMATTED).\n\nPlease select a smaller file or compress the video before uploading."
                    failureCount += 1
                case 400:
                    alertTitle = "Bad Request"
                    alertMessage = bodyText
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
}
