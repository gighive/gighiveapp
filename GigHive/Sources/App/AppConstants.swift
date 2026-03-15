import Foundation

/// Application-wide constants
enum AppConstants {
    /// Maximum allowed file size for uploads: 6 GB
    /// Files exceeding this size will be rejected before upload begins
    static let MAX_UPLOAD_SIZE_BYTES: Int64 = 6_442_450_944
    static let CLOUDFLARE_SINGLE_REQUEST_LIMIT_BYTES: Int64 = 100_000_000
    
    /// Human-readable formatted string of the max upload size
    static var MAX_UPLOAD_SIZE_FORMATTED: String {
        ByteCountFormatter.string(fromByteCount: MAX_UPLOAD_SIZE_BYTES, countStyle: .file)
    }
    
    static var CLOUDFLARE_SINGLE_REQUEST_LIMIT_FORMATTED: String {
        ByteCountFormatter.string(fromByteCount: CLOUDFLARE_SINGLE_REQUEST_LIMIT_BYTES, countStyle: .file)
    }
}
