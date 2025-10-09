import Foundation

/// Application-wide constants
enum AppConstants {
    /// Maximum allowed file size for uploads: 5 GB
    /// Files exceeding this size will be rejected before upload begins
    static let MAX_UPLOAD_SIZE_BYTES: Int64 = 5_368_709_120
    
    /// Human-readable formatted string of the max upload size
    static var MAX_UPLOAD_SIZE_FORMATTED: String {
        ByteCountFormatter.string(fromByteCount: MAX_UPLOAD_SIZE_BYTES, countStyle: .file)
    }
}
