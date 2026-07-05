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
                    // Post-upload thank-you state (after guestSession.clear())
                    GHCard(pad: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upload received — thank you!")
                                .font(.headline)
                                .ghForeground(GHTheme.text)
                            Text("Your video has been submitted to the event organizer.")
                                .font(.subheadline)
                                .ghForeground(GHTheme.muted)
                            Button("Dismiss") {
                                presentationMode.wrappedValue.dismiss()
                            }
                            .buttonStyle(GHButtonStyle(color: GHTheme.accent))
                        }
                    }

                } else if let details = guestSession.eventDetails {
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
                                GHLabel(text: "Your name (optional)")
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

                            Toggle(isOn: $guestSession.tosAccepted) {
                                VStack(alignment: .leading, spacing: 2) {
                                    GHLabel(text: "I accept the Terms of Service *")
                                    Text("By uploading, you confirm you have the right to share this content.")
                                        .font(.caption2)
                                        .ghForeground(GHTheme.muted)
                                }
                            }
                            .ghTint(GHTheme.accent)

                            VStack(alignment: .leading, spacing: 6) {
                                GHLabel(text: "Video file *")
                                Menu {
                                    Button("From Photos") {
                                        showPhotosPicker = true
                                    }
                                    Button("From Files") {
                                        showFilesPicker = true
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "paperclip")
                                        Text(fileURL?.lastPathComponent ?? "Choose Video")
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
                            }

                            if isUploading {
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
                                .padding(.vertical, 4)
                            }

                            Button(isUploading ? "Uploading…" : "Upload") {
                                Task { await doUpload() }
                            }
                            .buttonStyle(GHButtonStyle(color: GHTheme.accent))
                            .disabled(isUploading || fileURL == nil || !guestSession.tosAccepted)
                            .padding(.top, 2)

                            if !isUploading {
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
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
        .ghFullScreenBackground(GHTheme.bg)
        // .onAppear fires on first appearance; .onChange re-fires when rawToken changes
        // (e.g. user scans a second QR code while GuestUploadView is already on the stack).
        .onAppear {
            Task { await validateToken() }
        }
        .onChange(of: guestSession.rawToken) { _ in
            Task { await validateToken() }
        }
        .sheet(isPresented: $showPhotosPicker) {
            PHPickerView(selectionHandler: { url in
                showPhotosPicker = false
                fileURL = url
            })
            .modifier(PresentationDetentsCompat())
        }
        .sheet(isPresented: $showFilesPicker) {
            DocumentPickerView(
                allowedTypes: [UTType.movie, UTType.mpeg4Movie],
                onPick: { url in
                    showFilesPicker = false
                    fileURL = url
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
              let base = guestSession.baseURL else { return }
        tokenError = nil
        isLoadingToken = true
        do {
            guestSession.eventDetails = try await QRTokenAPIClient(baseURL: base).validateToken(token)
        } catch {
            tokenError = error.localizedDescription
        }
        isLoadingToken = false
    }

    private func missingFields() -> [String] {
        var msgs: [String] = []
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
            displayName: guestSession.displayName
        )

        let client = UploadClient(
            baseURL: baseURL,
            basicAuth: nil,
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

    private func handleFinalizeResponse(status: Int, data: Data, host: String) {
        switch status {
        case 200, 201:
            if let resp = try? JSONDecoder().decode(FinalizeResponse.self, from: data) {
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
            } else if let bodyText = String(data: data, encoding: .utf8),
                      let candidate = extractJSONCandidate(bodyText),
                      let candData = candidate.data(using: .utf8),
                      let resp = try? JSONDecoder().decode(FinalizeResponse.self, from: candData) {
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
            }
            guestSession.clear()
        case 404:
            alertTitle = "Link Expired"
            alertMessage = "This upload link is no longer valid. Please ask the event organizer for a new QR code."
            showResultAlert = true
        case 400:
            alertTitle = "Invalid Request"
            alertMessage = String(data: data, encoding: .utf8) ?? "Bad request"
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
