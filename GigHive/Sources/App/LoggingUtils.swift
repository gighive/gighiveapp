import Foundation

/// Logs a message with ISO 8601 timestamp prefix
/// Format: [yyyy-MM-dd'T'HH:mm:ss.SSS] message
func logWithTimestamp(_ message: String) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: Date())
    print("[\(timestamp)] \(message)")
}
