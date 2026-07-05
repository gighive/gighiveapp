import SwiftUI

struct SplashView: View {
    @EnvironmentObject var session: AuthSession
    @EnvironmentObject var guestSession: GuestUploadSession
    @State private var goToLogin = false
    @State private var goToDatabase = false
    @State private var goToUpload = false
    @State private var goToGuestUpload = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
            // Centered bee logo and app name
            GeometryReader { geometry in
                VStack(spacing: 16) {
                    Image("beelogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 0.66)
                    
                    Text("Gighive")
                        .font(.title3).bold()
                        .ghForeground(GHTheme.text)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 360)

            VStack(alignment: .leading, spacing: 4) {
                if let creds = session.credentials {
                    Text("User is logged into \(session.baseURL?.absoluteString ?? "<unknown>") as \(creds.user)")
                        .font(.footnote)
                        .foregroundColor(.orange)
                } else {
                    Text("Please login first")
                        .font(.subheadline).bold()
                        .foregroundColor(.orange)
                    Text("You will be able to View the Database or Upload a File based on your credentials")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }

            Button("Login") {
                logWithTimestamp("[Splash] Login tapped")
                goToLogin = true
            }
            .buttonStyle(GHButtonStyle(color: .orange))

            if session.credentials != nil {
                NavigationLink(destination: DatabaseView()) {
                    Text("View the Database")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    logWithTimestamp("[Splash] View Database tapped (direct nav)")
                    session.intendedRoute = .viewDatabase
                })
                .buttonStyle(GHButtonStyle(color: .blue))
            } else {
                Button("View the Database") {
                    logWithTimestamp("[Splash] View Database tapped (login redirect)")
                    session.intendedRoute = .viewDatabase
                    goToLogin = true
                }
                .buttonStyle(GHButtonStyle(color: .blue))
            }

            Button("Upload a File") {
                logWithTimestamp("[Splash] Upload tapped")
                session.intendedRoute = .upload
                if session.credentials == nil { 
                    goToLogin = true 
                } else {
                    goToUpload = true
                    // Clear intended route once navigation is triggered to avoid bounce on back
                    session.intendedRoute = nil
                }
            }
            .buttonStyle(GHButtonStyle(color: .green))

            // Hidden navigation links kept inside hierarchy for reliability on iOS 15
            NavigationLink(destination: LoginView(), isActive: $goToLogin) { EmptyView() }
                .frame(width: 0, height: 0)
                .hidden()
            NavigationLink(destination: UploadView(onUpload: { _ in 
                logWithTimestamp("[Splash] Upload finished callback")
            }), isActive: $goToUpload) { EmptyView() }
                .frame(width: 0, height: 0)
                .hidden()
            NavigationLink(destination: GuestUploadView(), isActive: $goToGuestUpload) { EmptyView() }
                .frame(width: 0, height: 0)
                .hidden()
            // goToDatabase no longer used with direct NavigationLink above but keep for safety
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .ghFullScreenBackground(GHTheme.bg)
            .onAppear { 
                logWithTimestamp("[Splash] appeared; loggedIn=\(session.credentials != nil)")
                if guestSession.rawToken != nil {
                    logWithTimestamp("[Splash] Guest token present, navigating to GuestUploadView")
                    goToGuestUpload = true
                } else if session.credentials != nil, session.intendedRoute == .upload {
                    logWithTimestamp("[Splash] Auto-navigating to Upload after login")
                    goToUpload = true
                    // Clear intended route so that Back from Upload returns to Splash cleanly
                    session.intendedRoute = nil
                }
            }
            .onChange(of: guestSession.rawToken) { token in
                if token != nil {
                    logWithTimestamp("[Splash] Guest token set while app open, navigating to GuestUploadView")
                    goToGuestUpload = true
                } else {
                    goToGuestUpload = false
                }
            }
            .onChange(of: goToLogin) { newVal in logWithTimestamp("[Splash] goToLogin=\(newVal)") }
            .onChange(of: goToDatabase) { newVal in logWithTimestamp("[Splash] goToDatabase=\(newVal)") }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(AppVersion.versionString)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(8)
                }
            }
        }
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
            .environmentObject(AuthSession())
            .environmentObject(UploadStateStore())
            .environmentObject(GuestUploadSession())
    }
}
