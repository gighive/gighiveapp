import Foundation

/// Decodes common HTML entities in a string (e.g. &quot; → ").
private func htmlEntityDecode(_ s: String) -> String {
    var r = s
    r = r.replacingOccurrences(of: "&quot;", with: "\"")
    r = r.replacingOccurrences(of: "&amp;",  with: "&")
    r = r.replacingOccurrences(of: "&lt;",   with: "<")
    r = r.replacingOccurrences(of: "&gt;",   with: ">")
    r = r.replacingOccurrences(of: "&#39;",  with: "'")
    r = r.replacingOccurrences(of: "&apos;", with: "'")
    return r
}

/// Extracts a JSON object string from a response body that may be wrapped in HTML.
/// Returns nil if no balanced JSON object containing known keys can be found.
func extractJSONCandidate(_ text: String) -> String? {
    // Prefer extracting JSON from <pre>...</pre> when server wraps JSON in HTML.
    // The <pre> content may be HTML-entity-encoded (e.g. &quot; for "), so decode first.
    if let preRange = text.range(of: "<pre", options: .caseInsensitive) {
        let tail = text[preRange.lowerBound...]
        if let gt = tail.firstIndex(of: ">") {
            let after = tail.index(after: gt)
            let rest = String(tail[after...])
            if let endPreRange = rest.range(of: "</pre>", options: .caseInsensitive) {
                let raw = String(rest[..<endPreRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let inner = htmlEntityDecode(raw)
                if let start = inner.firstIndex(of: "{"), let end = inner.lastIndex(of: "}"), start <= end {
                    logWithTimestamp("[FinalizeResponseHandler] Extracted JSON from <pre> block (entity-decoded)")
                    return String(inner[start...end])
                }
            }
        }
    }

    // If the HTML contains CSS (e.g. style blocks), naive "first { ... }" matching will
    // often capture CSS braces, not JSON. Anchor extraction around "id" or "delete_token".
    let anchorKeys = ["\"delete_token\"", "\"id\""]
    let lower = text
    var anchorIndex: String.Index? = nil
    for k in anchorKeys {
        if let r = lower.range(of: k, options: .caseInsensitive) {
            anchorIndex = r.lowerBound
            break
        }
    }

    guard let a = anchorIndex else {
        logWithTimestamp("[FinalizeResponseHandler] No JSON anchor (id/delete_token) found in finalize body")
        return nil
    }

    // Walk backwards to a '{' and then brace-match forward to a full JSON object.
    var startIdx = a
    while startIdx > lower.startIndex {
        let prev = lower.index(before: startIdx)
        if lower[prev] == "{" {
            startIdx = prev
            break
        }
        startIdx = prev
    }
    if lower[startIdx] != "{" {
        logWithTimestamp("[FinalizeResponseHandler] Could not find '{' before JSON anchor")
        return nil
    }

    let chars = Array(lower[startIdx...])
    var depth = 0
    var inString = false
    var escape = false
    for j in 0..<chars.count {
        let c = chars[j]
        if inString {
            if escape {
                escape = false
            } else if c == "\\" {
                escape = true
            } else if c == "\"" {
                inString = false
            }
            continue
        }

        if c == "\"" {
            inString = true
            continue
        }
        if c == "{" {
            depth += 1
        } else if c == "}" {
            depth -= 1
            if depth == 0 {
                let candidate = String(chars[0...j])
                logWithTimestamp("[FinalizeResponseHandler] Extracted JSON via anchor brace-match (len=\(candidate.count))")
                return candidate
            }
        }
    }

    logWithTimestamp("[FinalizeResponseHandler] Anchor brace-match did not find a balanced JSON object")
    return nil
}
