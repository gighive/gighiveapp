import SwiftUI

@MainActor
private func handleIncomingURL(_ url: URL, via source: String, guestSession: GuestUploadSession) {
    logWithTimestamp("[\(source)] parsing: \(url.absoluteString)")
    logWithTimestamp("[\(source)] pathComponents: \(url.pathComponents)")
    guard url.pathComponents.count >= 3 else {
        logWithTimestamp("[\(source)] BAIL: pathComponents.count=\(url.pathComponents.count) < 3")
        return
    }
    guard url.pathComponents[1] == "upload" else {
        logWithTimestamp("[\(source)] BAIL: pathComponents[1]='\(url.pathComponents[1])' != 'upload'")
        return
    }
    guard let host = url.host else {
        logWithTimestamp("[\(source)] BAIL: url.host is nil")
        return
    }
    guard let scheme = url.scheme else {
        logWithTimestamp("[\(source)] BAIL: url.scheme is nil")
        return
    }
    guard let baseURL = URL(string: "\(scheme)://\(host)") else {
        logWithTimestamp("[\(source)] BAIL: could not construct baseURL from \(scheme)://\(host)")
        return
    }
    let token = url.pathComponents[2]
    logWithTimestamp("[\(source)] guard passed — token=\(token.prefix(8))… baseURL=\(baseURL)")
    guestSession.baseURL = baseURL
    guestSession.rawToken = token
    logWithTimestamp("[\(source)] guestSession.rawToken set")
}

@main
struct GigHiveApp: App {
    @StateObject private var session = AuthSession()
    @StateObject private var uploadState = UploadStateStore()
    @StateObject private var guestSession = GuestUploadSession()
    var body: some Scene {
        WindowGroup {
            Group {
                if #available(iOS 16.0, *) {
                    NavigationStack {
                        SplashView()
                    }
                    .environmentObject(session)
                    .environmentObject(uploadState)
                    .environmentObject(guestSession)
                } else {
                    NavigationView {
                        SplashView()
                    }
                    .environmentObject(session)
                    .environmentObject(uploadState)
                    .environmentObject(guestSession)
                    .navigationViewStyle(StackNavigationViewStyle())
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else {
                    logWithTimestamp("[onContinueUserActivity] BAIL: webpageURL is nil")
                    return
                }
                logWithTimestamp("[onContinueUserActivity] fired: \(url.absoluteString)")
                handleIncomingURL(url, via: "onContinueUserActivity", guestSession: guestSession)
            }
            .onOpenURL { url in
                logWithTimestamp("[onOpenURL] fired: \(url.absoluteString)")
                handleIncomingURL(url, via: "onOpenURL", guestSession: guestSession)
            }
        }
    }
}
