import Foundation
import SwiftUI

final class AuthSession: ObservableObject {
    @Published var baseURL: URL?
    @Published var credential: AuthCredential?
    @Published var allowInsecureTLS: Bool = false
    @Published var role: UserRole = .unknown
    @Published var intendedRoute: AppRoute? = nil // .viewDatabase or .upload
}

enum UserRole { case unknown, viewer, contributor, owner }
enum AppRoute { case viewDatabase, upload }
