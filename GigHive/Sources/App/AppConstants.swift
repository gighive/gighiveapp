import Foundation

/// Application-wide constants
enum AppConstants {
    /// Maximum allowed file size for uploads: 6 GB
    /// Files exceeding this size will be rejected before upload begins
    static let MAX_UPLOAD_SIZE_BYTES: Int64 = 6_442_450_944
    
    /// Human-readable formatted string of the max upload size
    static var MAX_UPLOAD_SIZE_FORMATTED: String {
        ByteCountFormatter.string(fromByteCount: MAX_UPLOAD_SIZE_BYTES, countStyle: .file)
    }
}
