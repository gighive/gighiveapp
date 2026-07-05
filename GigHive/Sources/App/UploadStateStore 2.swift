import Foundation
import SwiftUI

@MainActor
final class UploadStateStore: ObservableObject {
    @Published var fileURL: URL?
    @Published var eventDate = Date()
    @Published var orgName = ""
    @Published var eventType = "band"
    @Published var label = ""
    @Published var autogenLabel = false
    @Published var isUploading = false
    @Published var isCancelling = false
    @Published var showResultAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var debugLog: [String] = []
    @Published var successURL: URL?
    @Published var failureCount: Int = 0
    @Published var lastButtonStatus: String?
    @Published var isLoadingMedia = false
    @Published var loadedFileSize: String?
    @Published var mediaLoadingStartedAt: Date?
    @Published var lastProgressBucket: Int = 0
    @Published var photoCopyProgress: Double?
    @Published var uploadProgress: Double?

    var uploadTask: Task<Void, Never>?
    var currentUploadClient: UploadClient?
    var cancelPreparingMedia: (() -> Void)?
}
