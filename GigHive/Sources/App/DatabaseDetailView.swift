import SwiftUI

struct DatabaseDetailView: View {
    let entry: MediaEntry
    let baseURL: URL
    @EnvironmentObject var session: AuthSession

    /// Maps entry.fileType string to the typed enum. Fallback to .video is safe:
    /// AVPlayerViewController handles both video and audio regardless of which UI
    /// path is chosen, so an unrecognised fileType should not suppress playback.
    private var fileType: MediaFileType {
        let mapped = MediaFileType(rawValue: entry.fileType) ?? .video
        if MediaFileType(rawValue: entry.fileType) == nil {
            logWithTimestamp("[Detail] Unrecognised fileType='\(entry.fileType)' for id=\(entry.id); falling back to .video")
        }
        return mapped
    }

    /// Resolves the stream URL from the relative entry.url against baseURL.
    private var streamURL: URL? {
        URL(string: entry.url, relativeTo: baseURL)
    }

    var body: some View {
        List {
            Section(header: Text("Media Info")) {
                DetailRow(label: "Date", value: entry.date)
                DetailRow(label: "Band/Event", value: entry.orgName)
                DetailRow(label: "Song Title", value: entry.songTitle)
                DetailRow(label: "Duration", value: entry.duration)
                DetailRow(label: "File Type", value: entry.fileType)
                DetailRow(label: "File Name", value: entry.fileName)
            }

            Section {
                if let url = streamURL {
                    // NOTE: Do not attach .simultaneousGesture(TapGesture()) to a NavigationLink
                    // inside a List — it consumes the row-selection tap and the link never
                    // activates (proven on device: 14 taps logged, zero pushes). The open log
                    // fires from the player's onAppear callback instead.
                    NavigationLink(destination: UnifiedVideoPlayerView(
                        config: UnifiedVideoPlayerConfig(
                            url: url,
                            credential: session.credential,
                            allowInsecureTLS: session.allowInsecureTLS,
                            fileType: fileType
                        ),
                        onAppear: {
                            logWithTimestamp("[Detail] Player opened; type=\(entry.fileType); file=\(entry.fileName)")
                        }
                    )) {
                        HStack {
                            Image(systemName: fileType == .video ? "play.circle.fill" : "music.note")
                            Text(fileType == .video ? "Play Video" : "Play Audio")
                            Spacer()
                            Image(systemName: "play.rectangle")
                        }
                    }
                    .accessibilityIdentifier("detail_play_button")
                } else {
                    Text("Media URL unavailable")
                        .foregroundColor(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Media Details")
        .navigationBarTitleDisplayMode(.inline)
        .ghFullScreenBackground(GHTheme.bg)
        .onAppear {
            logWithTimestamp("[Detail] Appeared; id=\(entry.id); type=\(entry.fileType); file=\(entry.fileName)")
        }
        // MediaPlayerView.swift becomes dead code after this step — removed in Step 13.
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label).ghForeground(GHTheme.muted)
            Spacer()
            Text(value).ghForeground(GHTheme.text)
                .multilineTextAlignment(.trailing)
        }
    }
}
