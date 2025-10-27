import SwiftUI

struct DatabaseView: View {
    @EnvironmentObject var session: AuthSession

    @State private var entries: [MediaEntry] = []
    @State private var filteredEntries: [MediaEntry] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // iOS 14 fallback search field
            if #unavailable(iOS 15.0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.orange)
                    TextField("Search by band, song, or date", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.vertical, 6)
                }
                .padding(.horizontal, 10)
                .ghBackgroundMaterial()
                .cornerRadius(8)
                .padding(.horizontal, 8)
            }

            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading database…").foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if let error = errorMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).foregroundColor(.red)
                        Button("Retry") { Task { await loadData() } }
                            .buttonStyle(GHButtonStyle(color: .blue))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
                } else if filteredEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No media found").foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
                } else {
                    if #available(iOS 15.0, *) {
                        List {
                            ForEach(filteredEntries) { entry in
                                NavigationLink(destination: DatabaseDetailView(entry: entry, baseURL: session.baseURL ?? URL(string: "https://example.com")!)) {
                                    MediaEntryRow(entry: entry)
                                }
                            }
                        }
                        .searchable(text: $searchText, placement: .automatic, prompt: "Search by band, song, or date")
                        .refreshable { await loadData() }
                    } else {
                        List {
                            ForEach(filteredEntries) { entry in
                                NavigationLink(destination: DatabaseDetailView(entry: entry, baseURL: session.baseURL ?? URL(string: "https://example.com")!)) {
                                    MediaEntryRow(entry: entry)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Media Database")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            logWithTimestamp("[DB] View appeared")
            Task { await loadData() }
        }
        .onChange(of: searchText) { _ in filterEntries() }
        .ghFullScreenBackground(GHTheme.bg)
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let baseURL = session.baseURL else {
            errorMessage = "Missing base URL"
            logWithTimestamp("[DB] Load aborted: missing baseURL")
            return
        }
        logWithTimestamp("[DB] Loading from base=\(baseURL.absoluteString), insecureTLS=\(session.allowInsecureTLS), user=\(session.credentials?.user ?? "<none>")")
        do {
            let client = DatabaseAPIClient(baseURL: baseURL, basicAuth: session.credentials, allowInsecure: session.allowInsecureTLS)
            let list = try await client.fetchMediaList()
            entries = list
            filteredEntries = list
            logWithTimestamp("[DB] Loaded entries count=\(list.count)")
        } catch {
            errorMessage = error.localizedDescription
            logWithTimestamp("[DB] Error: \(error.localizedDescription)")
        }
    }

    private func filterEntries() {
        if searchText.isEmpty {
            filteredEntries = entries
        } else {
            let q = searchText.lowercased()
            filteredEntries = entries.filter { e in
                e.orgName.lowercased().contains(q) ||
                e.songTitle.lowercased().contains(q) ||
                e.date.contains(q) ||
                e.fileType.lowercased().contains(q)
            }
        }
    }
}

struct MediaEntryRow: View {
    let entry: MediaEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date)
                    .font(.caption)
                    .ghForeground(GHTheme.muted)
                Spacer()
                Text(entry.fileType.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.fileType == "video" ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                    .cornerRadius(4)
            }
            Text(entry.orgName).font(.headline).ghForeground(GHTheme.text)
            HStack {
                Text(entry.songTitle).font(.subheadline).ghForeground(GHTheme.muted)
                Spacer()
                Text(entry.duration).font(.caption).ghForeground(GHTheme.muted)
            }
        }
        .padding(.vertical, 4)
    }
}
