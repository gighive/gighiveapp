import Foundation

// MARK: - VideoListContext

/// Encapsulates everything that differs between guest and authenticated use cases.
/// The UI layer (UnifiedVideoListView, UnifiedVideoPlayerView) is identical for all users;
/// context determines auth identity, API routing, and capability flags.
///
/// Note: AuthSession is an @EnvironmentObject and must not be stored as an associated value
/// directly — its @Published properties would not trigger view updates when the session
/// object changes (e.g. on token refresh). Instead, pass only the stable value-type fields
/// (baseURL, credential, allowInsecureTLS) at construction time.
enum VideoListContext {
    case guest(record: GuestUploadRecord)
    case authenticated(baseURL: URL, credential: AuthCredential?, allowInsecureTLS: Bool)
}

// MARK: - VideoListCapabilities

/// Derived from VideoListContext. Drives all conditional UI in UnifiedVideoListView
/// and UnifiedVideoPlayerView — no magic strings or scattered conditionals.
struct VideoListCapabilities {
    /// true for guest (flag/report system active); false for authenticated
    let canFlag: Bool
    /// false for guest; true for authenticated (search bar rendered)
    let canSearch: Bool
    /// true for guest (30-second live poll + scene-phase trigger); false for authenticated
    let canLivePoll: Bool
    /// true for both contexts — "New" badge rendered for unviewed entries
    let canShowNewBadge: Bool
    /// Determines which rows show the delete button
    let deleteScope: DeleteScope
}

extension VideoListContext {
    /// Derives capabilities from context. Single source of truth — no capability logic
    /// scattered in views.
    var capabilities: VideoListCapabilities {
        switch self {
        case .guest:
            return VideoListCapabilities(
                canFlag: true,
                canSearch: false,
                canLivePoll: true,
                canShowNewBadge: true,
                deleteScope: .uploaderOnly
            )
        case .authenticated:
            return VideoListCapabilities(
                canFlag: false,
                canSearch: true,
                canLivePoll: false,
                canShowNewBadge: true,
                deleteScope: .none  // Phase 4: changes to .uploaderAndAdmin when server prereq is met
            )
        }
    }
}

// MARK: - DeleteScope

enum DeleteScope {
    /// No delete capability for this context (authenticated path until Phase 4)
    case none
    /// Guest: delete shown only for the user's own uploads (nonce match via ownUploadIds)
    case uploaderOnly
    /// Authenticated admin/uploader: blocked on JWT role claim — see Phase 4
    case uploaderAndAdmin
}

// MARK: - UnifiedVideo

/// Normalized video model used by both UnifiedVideoListView and UnifiedVideoPlayerView.
/// Constructed from GuestGalleryVideo (guest path) or MediaEntry (authenticated path)
/// inside the respective data-loading functions.
struct UnifiedVideo: Identifiable {
    /// uploadJobId (guest) or MediaEntry.id (authenticated)
    let id: Int
    /// Attendee/submitter display name — guest: from API response; authenticated: nil until Phase 3 server prereq
    let displayName: String?
    /// Band/artist name — authenticated: MediaEntry.orgName; guest: nil (not in guest API response)
    let orgName: String?
    /// Clip label / song title
    let label: String?
    /// Direct playback URL (fully resolved; nil entries are skipped at mapping time)
    let streamURL: URL
    /// Video thumbnail — nil for authenticated path until server prereq; nil if absent in guest response
    let thumbnailURL: URL?
    /// Typed media kind — replaces magic "video" / "audio" string literals
    let fileType: MediaFileType
    /// true when this entry belongs to the current user (guest: nonce match; authenticated: Phase 4)
    let isOwnUpload: Bool
    /// true when this entry has been flagged/reported by the current user
    let isReported: Bool
}

// MARK: - MediaFileType

/// Typed replacement for the "video" / "audio" magic strings in MediaEntry.fileType,
/// MediaPlayerView, and DatabaseView. RawRepresentable conformance via String allows
/// direct mapping from MediaEntry.fileType with a safe fallback:
///   MediaFileType(rawValue: entry.fileType) ?? .video
enum MediaFileType: String {
    case video
    case audio
}
