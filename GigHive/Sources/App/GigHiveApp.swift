import SwiftUI

@main
struct GigHiveApp: App {
    @StateObject private var session = AuthSession()
    @StateObject private var uploadState = UploadStateStore()
    var body: some Scene {
        WindowGroup {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    SplashView()
                }
                .environmentObject(session)
                .environmentObject(uploadState)
            } else {
                NavigationView {
                    SplashView()
                }
                .environmentObject(session)
                .environmentObject(uploadState)
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }
}
