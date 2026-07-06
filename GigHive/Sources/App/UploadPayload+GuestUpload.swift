import Foundation

extension UploadPayload {
    /// Shared static formatter — DateFormatter allocation is expensive; reuse across calls.
    private static let eventDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private static let labelFallbackFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    static func forGuestUpload(
        fileURL: URL,
        eventDetails: QREventDetails,
        displayName: String,
        clipLabel: String = ""
    ) -> UploadPayload {
        let eventDate = eventDateFormatter.date(from: eventDetails.eventDate) ?? Date()
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = clipLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = trimmedLabel.isEmpty
            ? "Video \(labelFallbackFormatter.string(from: Date()))"
            : trimmedLabel
        return UploadPayload(
            fileURL: fileURL,
            eventDate: eventDate,
            orgName: eventDetails.orgName,
            eventType: eventDetails.eventType,
            label: resolvedLabel,
            displayName: trimmedName.isEmpty ? nil : String(trimmedName.prefix(100)),
            tosAccepted: true
        )
    }
}
