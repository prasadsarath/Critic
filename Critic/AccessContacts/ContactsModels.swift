import Foundation

// App user found by phone lookup
struct RegisteredContact: Identifiable, Equatable, Codable {
    let id: String            // userId on Critic
    let name: String?
    let phoneE164: String     // optional for UI; can be empty when we don't render phones
}

// Local device contact (may or may not be on Critic)
struct LocalContact: Identifiable, Equatable {
    let id: String
    let displayName: String
    let phones: [String]          // raw user-visible numbers
    let normalizedPhones: [String]// E.164-like (best effort)
}

/// Best-effort E.164 normalization without libPhoneNumber:
/// - Keep digits and '+'
/// - If no '+' and 10 digits, assume +1 (US) — adjust as needed
func normalizeToE164ish(_ s: String, defaultCountryCode: String = "+1") -> String {
    let kept = s.filter { ("0"..."9").contains($0) || $0 == "+" }
    if kept.hasPrefix("+") { return kept }
    let digits = kept.filter { ("0"..."9").contains($0) }
    if digits.count == 10 { return defaultCountryCode + digits }
    if !digits.isEmpty { return defaultCountryCode + digits }
    return kept
}

