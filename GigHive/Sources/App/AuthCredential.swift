import Foundation

/// Encapsulates GigHive authentication material for a single session.
/// Owns Authorization header production — call sites never construct headers directly.
enum AuthCredential {
    /// Legacy HTTP Basic Auth — username + password.
    case basic(user: String, pass: String)
    /// JWT Bearer token issued by GigHive (local login or OIDC exchange).
    case bearer(token: String)
    /// QR event upload token — sent as X-Upload-Token, not Authorization.
    case uploadToken(String)

    /// Returns the value for the `Authorization` header, or nil for uploadToken
    /// (which uses a separate header — see `uploadTokenHeaderValue`).
    var authorizationHeaderValue: String? {
        switch self {
        case .basic(let user, let pass):
            let raw = "\(user):\(pass)"
            return "Basic \(Data(raw.utf8).base64EncodedString())"
        case .bearer(let token):
            return "Bearer \(token)"
        case .uploadToken:
            return nil
        }
    }

    /// Returns the value for the `X-Upload-Token` header, or nil for non-upload-token credentials.
    var uploadTokenHeaderValue: String? {
        if case .uploadToken(let t) = self { return t }
        return nil
    }

    /// Applies the appropriate auth header(s) to a URLRequest in place.
    func apply(to request: inout URLRequest) {
        if let value = authorizationHeaderValue {
            request.setValue(value, forHTTPHeaderField: "Authorization")
        }
        if let value = uploadTokenHeaderValue {
            request.setValue(value, forHTTPHeaderField: "X-Upload-Token")
        }
    }

    /// Applies the appropriate auth header(s) to an AVURLAsset / TUSUploadClient header dict.
    func apply(to headers: inout [String: String]) {
        if let value = authorizationHeaderValue {
            headers["Authorization"] = value
        }
        if let value = uploadTokenHeaderValue {
            headers["X-Upload-Token"] = value
        }
    }

    /// Human-readable identifier for display and logging — username for .basic, nil for others.
    var displayUser: String? {
        switch self {
        case .basic(let user, _): return user
        case .bearer: return nil   // role/email will be decoded from JWT in Phase 3
        case .uploadToken: return nil
        }
    }
}
