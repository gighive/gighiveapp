import SwiftUI

@main
struct GigHiveApp: App {
    @StateObject private var session = AuthSession()
    var body: some Scene {
        WindowGroup {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    SplashView()
                }
                .environmentObject(session)
            } else {
                NavigationView {
                    SplashView()
                }
                .environmentObject(session)
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }
}
