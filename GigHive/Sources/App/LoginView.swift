import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: AuthSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var base: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var disableCertChecking: Bool = false
    @State private var rememberOnDevice: Bool = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let lastHostDefaultsKey = "gh_last_host"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TitleHeaderView(title: "Gighive Login")

                GHCard(pad: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        GHLabel(text: "SERVER")
                        HStack(spacing: 4) {
                            Text("https://")
                                .font(.caption2)
                                .ghForeground(GHTheme.muted)
                            NoAccessoryTextField(
                                text: $base,
                                placeholder: "example.com",
                                keyboardType: .URL,
                                autocapitalizationType: .none,
                                autocorrectionType: .no
                            )
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .ghBackgroundMaterial()
                        .cornerRadius(6)

                        GHLabel(text: "USERNAME")
                        NoAccessoryTextField(
                            text: $username,
                            placeholder: "viewer or admin",
                            keyboardType: .default,
                            autocapitalizationType: .none,
                            autocorrectionType: .no,
                            textContentType: .username
                        )
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .ghBackgroundMaterial()
                        .cornerRadius(6)

                        GHLabel(text: "PASSWORD")
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

                        Toggle(isOn: $rememberOnDevice) {
                            Text("Remember on this device").font(.caption2).ghForeground(GHTheme.muted)
                        }
                        .ghTint(GHTheme.accent)
                        .padding(.top, 4)

                        Toggle(isOn: $disableCertChecking) {
                            Text("Disable Certificate Checking").font(.caption2).ghForeground(GHTheme.muted)
                        }
                        .ghTint(GHTheme.accent)
                        .padding(.top, 4)
                    }
                }

                if let error = errorMessage {
                    Text(error).foregroundColor(.red)
                }

                HStack {
                    Button(isLoading ? "Signing In…" : "Sign In") { 
                        logWithTimestamp("[Login] Sign in tapped")
                        Task { await signIn() } 
                    }
                        .buttonStyle(GHButtonStyle(color: .orange))
                        .disabled(isLoading)

                    Button("Cancel") { 
                        logWithTimestamp("[Login] Cancel tapped")
                        dismissCompat() 
                    }
                        .buttonStyle(GHButtonStyle(color: .red))
                }
            }
            .padding()
        }
        .ghFullScreenBackground(GHTheme.bg)
        .onAppear {
            logWithTimestamp("[Login] appeared")
            // Attempt to prefill from Keychain using current server host if present
            let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
            let full = trimmed.hasPrefix("http") ? trimmed : "https://" + trimmed
            if let host = URL(string: full)?.host, !host.isEmpty {
                if let creds = try? KeychainStore.load(host: host) {
                    logWithTimestamp("[Login] Loaded saved creds for host=\(host)")
                    self.username = creds.user
                    self.password = creds.pass
                }
            } else if let lastHost = UserDefaults.standard.string(forKey: lastHostDefaultsKey), !lastHost.isEmpty {
                // Prefill server host and credentials if we have a remembered host
                self.base = lastHost
                if let creds = try? KeychainStore.load(host: lastHost) {
                    logWithTimestamp("[Login] Loaded saved creds for lastHost=\(lastHost)")
                    self.username = creds.user
                    self.password = creds.pass
                }
            }
        }
    }

    private func signIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = trimmed.hasPrefix("http") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), url.scheme?.hasPrefix("http") == true else {
            errorMessage = "Invalid URL"; return
        }
        logWithTimestamp("[Login] Sign in started for host=\(full)")
        // Perform lightweight validation against the server using provided credentials
        do {
            let client = DatabaseAPIClient(
                baseURL: url,
                basicAuth: (username, password),
                allowInsecure: disableCertChecking
            )
            let entries = try await client.fetchMediaList()
            logWithTimestamp("[Login] Auth response: 200 (entries: \(entries.count))")
        } catch {
            if let dbErr = error as? DatabaseError {
                switch dbErr {
                case .httpError(let code):
                    logWithTimestamp("[Login] Auth response: \(code)")
                default:
                    logWithTimestamp("[Login] Auth error: \(dbErr.localizedDescription)")
                }
            } else {
                logWithTimestamp("[Login] Auth error: \(error.localizedDescription)")
            }
            errorMessage = error.localizedDescription
            return
        }

        // On success, persist into session and dismiss
        session.baseURL = url
        session.credentials = (username, password)
        session.allowInsecureTLS = disableCertChecking
        // Derive role from username for now (server doesn't return role yet)
        let lowered = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        session.role = (lowered == "admin") ? .admin : .viewer
        if let host = url.host, !host.isEmpty {
            do {
                if rememberOnDevice {
                    try KeychainStore.save(user: username, pass: password, host: host)
                    logWithTimestamp("[Login] Saved creds to device for host=\(host)")
                    UserDefaults.standard.set(host, forKey: lastHostDefaultsKey)
                } else {
                    try KeychainStore.delete(host: host)
                    logWithTimestamp("[Login] Deleted saved creds for host=\(host)")
                    // Only clear lastHost if it matches
                    if UserDefaults.standard.string(forKey: lastHostDefaultsKey) == host {
                        UserDefaults.standard.removeObject(forKey: lastHostDefaultsKey)
                    }
                }
            } catch {
                logWithTimestamp("[Login] Keychain error: \(error.localizedDescription)")
            }
        }
        logWithTimestamp("[Login] Auth success; dismissing")
        dismissCompat()
    }

    private func dismissCompat() {
        presentationMode.wrappedValue.dismiss()
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView().environmentObject(AuthSession())
            .ghFullScreenBackground(GHTheme.bg)
    }
}
