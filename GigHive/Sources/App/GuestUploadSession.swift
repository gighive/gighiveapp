import Foundation
import SwiftUI

struct QREventDetails: Codable {
    let eventDate: String
    let orgName: String
    let eventType: String
    let title: String?
    let tokenId: Int?

    enum CodingKeys: String, CodingKey {
        case eventDate = "event_date"
        case orgName = "org_name"
        case eventType = "event_type"
        case title
        case tokenId = "token_id"
    }
}

@MainActor
final class GuestUploadSession: ObservableObject {
    @Published var rawToken: String?
    @Published var baseURL: URL?
    @Published var eventDetails: QREventDetails?
    @Published var displayName: String = ""
    @Published var tosAccepted: Bool = false

    func clear() {
        rawToken = nil
        baseURL = nil
        eventDetails = nil
        displayName = ""
        tosAccepted = false
    }
}
