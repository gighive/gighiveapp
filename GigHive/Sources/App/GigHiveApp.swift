import SwiftUI

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
            .onOpenURL { url in
                guard url.pathComponents.count >= 3,
                      url.pathComponents[1] == "upload",
                      let host = url.host,
                      let scheme = url.scheme,
                      let baseURL = URL(string: "\(scheme)://\(host)") else { return }
                Task { @MainActor in
                    guestSession.baseURL = baseURL
                    guestSession.rawToken = url.pathComponents[2]
                }
            }
        }
    }
}
