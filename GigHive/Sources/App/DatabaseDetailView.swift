import SwiftUI

struct DatabaseDetailView: View {
    let entry: MediaEntry
    let baseURL: URL
    @EnvironmentObject var session: AuthSession
    @State private var showPlayer = false
    
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
                Button(action: {
                    logWithTimestamp("[Detail] Play tapped; type=\(entry.fileType); file=\(entry.fileName)")
                    showPlayer = true
                }) {
                    HStack {
                        Image(systemName: entry.fileType == "video" ? "play.circle.fill" : "music.note")
                        Text(entry.fileType == "video" ? "Play Video" : "Play Audio")
                        Spacer()
                        Image(systemName: "play.rectangle")
                    }
                }
                
                if let url = URL(string: entry.url, relativeTo: baseURL) {
                    if #available(iOS 16.0, *) {
                        ShareLink(item: url) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            logWithTimestamp("[Detail] Share tapped; file=\(entry.fileName)")
                        })
                    } else {
                        Button(action: { 
                            logWithTimestamp("[Detail] Share tapped; file=\(entry.fileName)")
                            ShareHelper.present(url) 
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                        }
                    }
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
        .sheet(isPresented: $showPlayer) {
            MediaPlayerView(
                baseURL: baseURL,
                entry: entry,
                credentials: session.credentials,
                allowInsecureTLS: session.allowInsecureTLS
            )
        }
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
