import CoreLocation
import SwiftUI
import UIKit

struct Theme {
    static let background = CriticPalette.background
    static let surface = CriticPalette.surface
    static let surfaceVariant = CriticPalette.surfaceVariant
    static let tint = CriticPalette.primary
    static let accent = CriticPalette.accent
    static let subtleText = CriticPalette.onSurfaceMuted
    static let outline = CriticPalette.outline
    static let success = CriticPalette.success
    static let warning = CriticPalette.warning
    static let error = CriticPalette.error
    static let info = CriticPalette.info
}

enum NearbyLocationPolicy {
    static let maxHorizontalAccuracy: CLLocationAccuracy = 10
    static let maxIncomingLocationAge: TimeInterval = 3
    static let maxLiveLocationAge: TimeInterval = 5
    static let maxStoredLocationAge: TimeInterval = 15
    static let onlineFreshnessInterval: TimeInterval = 3
    static let offlineRetentionInterval: TimeInterval = 10
    static let smoothingWindowSize = 5
    static let temporaryFullAccuracyPurposeKey = "NearbyPrecisionLocation"
}

enum DisplayNameResolver {
    static func resolve(displayName: String?, email: String? = nil, phone: String? = nil, userId: String?) -> String {
        if let name = preferredName(displayName, userId: userId) {
            if let validEmail = normalizedEmail(name),
               let local = validEmail.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first {
                return String(local)
            }
            return name
        }

        if let email = normalizedEmail(email),
           let local = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first,
           let emailName = preferredName(String(local), userId: userId) {
            return emailName
        }

        if let userId,
           let currentId = UserDefaults.standard.string(forKey: "userId"),
           userId == currentId {
            if let storedName = preferredName(UserDefaults.standard.string(forKey: "userName"), userId: userId) {
                return storedName
            }
            if let email = normalizedEmail(UserDefaults.standard.string(forKey: "userEmail")),
               let local = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first,
               let emailName = preferredName(String(local), userId: userId) {
                return emailName
            }
            if let phoneLabel = phoneDisplayLabel(UserDefaults.standard.string(forKey: "userPhone")) {
                return phoneLabel
            }
        }

        if let cachedName = preferredName(KnownUserDirectory.name(for: userId), userId: userId) {
            return cachedName
        }

        if let cachedEmail = normalizedEmail(email ?? KnownUserDirectory.email(for: userId)),
           let local = cachedEmail.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first,
           let emailName = preferredName(String(local), userId: userId) {
            return emailName
        }

        if let cachedPhone = phoneDisplayLabel(phone ?? KnownUserDirectory.phone(for: userId)) {
            return cachedPhone
        }

        if let fallback = fallbackUserLabel(userId) {
            return fallback
        }

        return "Nearby"
    }

    static func homeHeaderName(storedName: String?, userId: String?, email: String?) -> String {
        if let name = preferredName(storedName, userId: userId) {
            return condensedHomeName(name)
        }
        if let email = normalizedEmail(email) {
            let local = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? email
            return condensedHomeName(local)
        }
        return "User"
    }

    static func preferredName(_ value: String?, userId: String?) -> String? {
        guard let trimmed = normalized(value) else { return nil }
        if let userId, trimmed == userId { return nil }
        if looksLikeOpaqueIdentifier(trimmed) { return nil }
        return trimmed
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("guest") == .orderedSame { return nil }
        if trimmed.caseInsensitiveCompare("guest@example.com") == .orderedSame { return nil }
        if trimmed.caseInsensitiveCompare("user") == .orderedSame { return nil }
        if trimmed.caseInsensitiveCompare("unknown") == .orderedSame { return nil }
        if trimmed.caseInsensitiveCompare("unknown user") == .orderedSame { return nil }
        return trimmed
    }

    static func normalizedEmail(_ value: String?) -> String? {
        guard let trimmed = normalized(value), trimmed.contains("@") else { return nil }
        return trimmed
    }

    static func normalizedPhone(_ value: String?) -> String? {
        guard let trimmed = normalized(value) else { return nil }
        let kept = trimmed.filter { $0.isNumber || $0 == "+" }
        guard kept.filter(\.isNumber).count >= 4 else { return nil }
        return kept
    }

    private static func condensedHomeName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }

        let firstToken = trimmed.split(whereSeparator: \.isWhitespace).first
        return firstToken.map(String.init) ?? trimmed
    }

    private static func looksLikeOpaqueIdentifier(_ value: String) -> Bool {
        let hyphenCount = value.filter { $0 == "-" }.count
        guard hyphenCount >= 3 else { return false }

        let compact = value.replacingOccurrences(of: "-", with: "")
        guard compact.count >= 16 else { return false }

        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return compact.unicodeScalars.allSatisfy { hexDigits.contains($0) }
    }

    private static func phoneDisplayLabel(_ value: String?) -> String? {
        guard let phone = normalizedPhone(value) else { return nil }
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 4 else { return nil }
        return String(digits.suffix(min(4, digits.count)))
    }

    private static func fallbackUserLabel(_ userId: String?) -> String? {
        guard let raw = normalized(userId) else { return nil }
        if looksLikeOpaqueIdentifier(raw) {
            let trimmed = raw.replacingOccurrences(of: "-", with: "")
            return String(trimmed.suffix(min(6, trimmed.count))).uppercased()
        }
        return raw
    }
}

enum KnownUserDirectory {
    private static let namesKey = "knownUserNames"
    private static let emailsKey = "knownUserEmails"
    private static let phonesKey = "knownUserPhones"
    private static let profileURLsKey = "knownUserProfileURLs"

    static func rememberCurrentUserFromDefaults() {
        let defaults = UserDefaults.standard
        remember(
            userId: defaults.string(forKey: "userId"),
            displayName: defaults.string(forKey: "userName"),
            email: defaults.string(forKey: "userEmail"),
            phone: defaults.string(forKey: "userPhone"),
            profileUrl: defaults.string(forKey: "userProfileUrl")
        )
    }

    static func remember(userId: String?, displayName: String?, email: String?, phone: String? = nil, profileUrl: String?) {
        guard let userId = DisplayNameResolver.normalized(userId) else { return }

        if let displayName = DisplayNameResolver.preferredName(displayName, userId: userId) {
            store(displayName, in: namesKey, for: userId)
        }

        if let email = DisplayNameResolver.normalizedEmail(email) {
            store(email, in: emailsKey, for: userId)
        }

        if let phone = DisplayNameResolver.normalizedPhone(phone) {
            store(phone, in: phonesKey, for: userId)
        }

        if let profileUrl = DisplayNameResolver.normalized(profileUrl) {
            store(profileUrl, in: profileURLsKey, for: userId)
        }
    }

    static func name(for userId: String?) -> String? {
        value(in: namesKey, for: userId)
    }

    static func email(for userId: String?) -> String? {
        value(in: emailsKey, for: userId)
    }

    static func phone(for userId: String?) -> String? {
        value(in: phonesKey, for: userId)
    }

    static func profileUrl(for userId: String?) -> String? {
        value(in: profileURLsKey, for: userId)
    }

    static func hydrated(_ user: UserLocation) -> UserLocation {
        let resolvedEmail = user.email ?? email(for: user.id)
        let resolvedPhone = user.phone ?? phone(for: user.id)
        let resolvedDisplayName = DisplayNameResolver.resolve(
            displayName: user.displayName ?? name(for: user.id),
            email: resolvedEmail,
            phone: resolvedPhone,
            userId: user.id
        )

        return UserLocation(
            id: user.id,
            latitude: user.latitude,
            longitude: user.longitude,
            profileImageName: user.profileImageName,
            displayName: resolvedDisplayName,
            email: resolvedEmail,
            phone: resolvedPhone,
            profileUrl: user.profileUrl ?? profileUrl(for: user.id),
            distanceMeters: user.distanceMeters,
            isSimulated: user.isSimulated,
            lastSeenAt: user.lastSeenAt
        )
    }

    private static func value(in key: String, for userId: String?) -> String? {
        guard let userId = DisplayNameResolver.normalized(userId),
              let store = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else {
            return nil
        }
        return store[userId]
    }

    private static func store(_ value: String, in key: String, for userId: String) {
        let defaults = UserDefaults.standard
        var store = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        store[userId] = value
        defaults.set(store, forKey: key)
    }
}

enum DicebearAvatar {
    static let defaultStyle = "bottts-neutral"
    static let defaultSize = 128

    static func url(seed: String, size: Int = defaultSize, style: String = defaultStyle) -> URL? {
        let trimmedSeed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSeed.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.dicebear.com"
        components.path = "/9.x/\(style)/png"
        components.queryItems = [
            URLQueryItem(name: "seed", value: trimmedSeed),
            URLQueryItem(name: "size", value: String(size))
        ]
        return components.url
    }
}

struct AvatarView: View {
    let urlString: String?
    let seed: String?
    let fallbackSystemName: String
    let size: CGFloat
    let backgroundColor: Color
    let tintColor: Color

    init(
        urlString: String?,
        seed: String? = nil,
        fallbackSystemName: String = "person.circle.fill",
        size: CGFloat = 42,
        backgroundColor: Color = Color(UIColor.secondarySystemBackground),
        tintColor: Color = .accentColor
    ) {
        self.urlString = urlString
        self.seed = seed
        self.fallbackSystemName = fallbackSystemName
        self.size = size
        self.backgroundColor = backgroundColor
        self.tintColor = tintColor
    }

    private var resolvedURL: URL? {
        if let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(string: urlString)
        }
        if let seed {
            return DicebearAvatar.url(seed: seed, size: pixelSize)
        }
        return nil
    }

    private var pixelSize: Int {
        let scale = UIScreen.main.scale
        let raw = Int(size * scale)
        return min(512, max(64, raw))
    }

    private var initials: String? {
        guard let seed else { return nil }
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-" })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }
        if parts.count == 1 {
            return String(parts[0].prefix(2)).uppercased()
        }
        return "\(parts[0].prefix(1))\(parts[parts.count - 1].prefix(1))".uppercased()
    }

    private var seededBackgroundColor: Color {
        let palette = [
            Color(hex: 0xDBEAFE),
            Color(hex: 0xD1FAE5),
            Color(hex: 0xFFEDD5),
            Color(hex: 0xEDE9FE),
            Color(hex: 0xFCE7F3),
            Color(hex: 0xE0F2FE)
        ]
        let token = (seed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return tintColor.opacity(0.14) }
        return palette[abs(token.hashValue) % palette.count]
    }

    private var avatarShell: some View {
        Circle()
            .fill(backgroundColor)
            .overlay(Circle().stroke(Theme.outline, lineWidth: 1))
    }

    var body: some View {
        if let url = resolvedURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    fallbackView
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .background(avatarShell)
                        .overlay(Circle().stroke(Theme.outline, lineWidth: 1))
                case .failure:
                    fallbackView
                @unknown default:
                    fallbackView
                }
            }
        } else {
            fallbackView
        }
    }

    private var fallbackView: some View {
        Group {
            if let initials, !initials.isEmpty {
                Text(initials)
                    .font(.custom("Manrope-Bold", size: size * 0.34))
                    .foregroundColor(tintColor.opacity(0.9))
                    .frame(width: size, height: size)
                    .background(Circle().fill(seededBackgroundColor))
            } else {
                Image(systemName: fallbackSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.24)
                    .frame(width: size, height: size)
                    .foregroundColor(tintColor)
                    .background(Circle().fill(backgroundColor))
            }
        }
        .overlay(Circle().stroke(Theme.outline, lineWidth: 1))
    }
}

struct UserLocation: Identifiable, Hashable {
    let id: String
    let latitude: Double
    let longitude: Double
    let profileImageName: String
    let displayName: String?
    let email: String?
    let phone: String?
    let profileUrl: String?
    let distanceMeters: Double?
    let isSimulated: Bool?
    let lastSeenAt: Date?

    static func == (lhs: UserLocation, rhs: UserLocation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(
        id: String,
        latitude: Double,
        longitude: Double,
        profileImageName: String,
        displayName: String?,
        email: String? = nil,
        phone: String? = nil,
        profileUrl: String? = nil,
        distanceMeters: Double? = nil,
        isSimulated: Bool? = nil,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.profileImageName = profileImageName
        self.displayName = displayName
        self.email = email
        self.phone = phone
        self.profileUrl = profileUrl
        self.distanceMeters = distanceMeters
        self.isSimulated = isSimulated
        self.lastSeenAt = lastSeenAt
    }
}

private enum NearbyPresenceDateParser {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum NearbyLocationStorageKey {
    static let latitude = "lastKnownLatitude"
    static let longitude = "lastKnownLongitude"
    static let horizontalAccuracy = "lastKnownHorizontalAccuracy"
    static let timestamp = "lastKnownLocationTimestamp"
}

/// Checks whether raw latitude and longitude values are usable for nearby calculations.
///
/// Rejects non-finite values, out-of-range coordinates, and the default zero-value placeholder
/// so distance math is only attempted with valid geographic points.
///
/// - Parameters:
///   - latitude: The latitude value to validate.
///   - longitude: The longitude value to validate.
/// - Returns: `true` when the coordinate is structurally valid for location work; otherwise `false`.
private func hasUsableCoordinate(latitude: Double, longitude: Double) -> Bool {
    guard latitude.isFinite, longitude.isFinite else { return false }
    guard abs(latitude) <= 90, abs(longitude) <= 180 else { return false }
    return abs(latitude) > .ulpOfOne || abs(longitude) > .ulpOfOne
}

/// Validates whether a `CLLocation` is accurate and fresh enough for nearby-user logic.
///
/// This helper combines coordinate sanity checks, `horizontalAccuracy` thresholds, and timestamp
/// freshness so the same quality gate is applied to live GPS fixes and cached locations.
///
/// - Parameters:
///   - location: The `CLLocation` being evaluated.
///   - maxAge: The maximum allowed age, in seconds, for the location fix.
///   - now: The reference time used to measure the fix age.
/// - Returns: `true` when the location is recent and accurate enough for nearby detection.
func isUsableNearbyLocation(
    _ location: CLLocation,
    maxAge: TimeInterval,
    now: Date = Date()
) -> Bool {
    guard hasUsableCoordinate(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude
    ) else {
        return false
    }
    guard location.horizontalAccuracy > 0,
          location.horizontalAccuracy <= NearbyLocationPolicy.maxHorizontalAccuracy else {
        return false
    }
    return abs(location.timestamp.timeIntervalSince(now)) <= maxAge
}

/// Loads the most recent persisted device location used by nearby features.
///
/// The stored fix is rebuilt from `UserDefaults` and then revalidated against the same freshness
/// and accuracy policy as live GPS updates before it can be reused by the UI or socket layer.
///
/// - Parameters:
///   - maxAge: The maximum age, in seconds, allowed for the stored location.
///   - now: The reference time used to evaluate the stored timestamp.
/// - Returns: A previously persisted `CLLocation`, or `nil` when the cached fix is missing or stale.
func currentStoredDeviceLocation(
    maxAge: TimeInterval = NearbyLocationPolicy.maxStoredLocationAge,
    now: Date = Date()
) -> CLLocation? {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: NearbyLocationStorageKey.latitude) != nil,
          defaults.object(forKey: NearbyLocationStorageKey.longitude) != nil,
          defaults.object(forKey: NearbyLocationStorageKey.horizontalAccuracy) != nil,
          defaults.object(forKey: NearbyLocationStorageKey.timestamp) != nil else {
        return nil
    }

    let latitude = defaults.double(forKey: NearbyLocationStorageKey.latitude)
    let longitude = defaults.double(forKey: NearbyLocationStorageKey.longitude)
    let horizontalAccuracy = defaults.double(forKey: NearbyLocationStorageKey.horizontalAccuracy)
    let timestamp = Date(timeIntervalSince1970: defaults.double(forKey: NearbyLocationStorageKey.timestamp))
    let storedLocation = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        altitude: 0,
        horizontalAccuracy: horizontalAccuracy,
        verticalAccuracy: -1,
        timestamp: timestamp
    )
    guard isUsableNearbyLocation(storedLocation, maxAge: maxAge, now: now) else { return nil }
    return storedLocation
}

/// Loads the most recent persisted nearby location without applying a timestamp freshness gate.
///
/// This is used as a stationary foreground fallback so nearby heartbeats can continue even when
/// Core Location pauses raw updates for a device that has not moved. Structural coordinate and
/// accuracy checks still apply, but the stored timestamp is allowed to be older than the normal
/// live/stored freshness thresholds.
///
/// - Returns: The last persisted `CLLocation`, or `nil` when cached values are missing or invalid.
func lastPersistedNearbyLocation() -> CLLocation? {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: NearbyLocationStorageKey.latitude) != nil,
          defaults.object(forKey: NearbyLocationStorageKey.longitude) != nil,
          defaults.object(forKey: NearbyLocationStorageKey.horizontalAccuracy) != nil,
          defaults.object(forKey: NearbyLocationStorageKey.timestamp) != nil else {
        return nil
    }

    let latitude = defaults.double(forKey: NearbyLocationStorageKey.latitude)
    let longitude = defaults.double(forKey: NearbyLocationStorageKey.longitude)
    let horizontalAccuracy = defaults.double(forKey: NearbyLocationStorageKey.horizontalAccuracy)
    let timestamp = Date(timeIntervalSince1970: defaults.double(forKey: NearbyLocationStorageKey.timestamp))
    let storedLocation = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        altitude: 0,
        horizontalAccuracy: horizontalAccuracy,
        verticalAccuracy: -1,
        timestamp: timestamp
    )

    guard hasUsableCoordinate(latitude: latitude, longitude: longitude) else { return nil }
    guard horizontalAccuracy > 0,
          horizontalAccuracy <= NearbyLocationPolicy.maxHorizontalAccuracy else {
        return nil
    }
    return storedLocation
}

/// Parses a nearby-user freshness timestamp returned by the socket backend.
///
/// The websocket payload currently returns ISO 8601 strings with and without fractional seconds,
/// so this helper normalizes both formats into `Date` values for client-side presence checks.
///
/// - Parameter rawValue: The raw timestamp string from the nearby-user payload.
/// - Returns: A parsed `Date`, or `nil` when the timestamp is missing or malformed.
func parseNearbyPresenceDate(_ rawValue: String?) -> Date? {
    guard let rawValue = DisplayNameResolver.normalized(rawValue) else { return nil }
    return NearbyPresenceDateParser.fractional.date(from: rawValue)
        ?? NearbyPresenceDateParser.plain.date(from: rawValue)
}

/// Indicates whether a nearby user should be considered currently online.
///
/// Presence is derived from the latest server timestamp we have for the user, with a short client
/// freshness window to tolerate one missed websocket cycle without instantly flipping offline.
///
/// - Parameters:
///   - user: The nearby user whose presence should be evaluated.
///   - now: The reference time used for freshness checks.
/// - Returns: `true` when the user was seen recently enough to be treated as online.
func isNearbyUserOnline(_ user: UserLocation, now: Date = Date()) -> Bool {
    guard let lastSeenAt = user.lastSeenAt else { return false }
    return abs(lastSeenAt.timeIntervalSince(now)) <= NearbyLocationPolicy.onlineFreshnessInterval
}

/// Indicates whether a nearby user should remain visible in the UI.
///
/// Users are retained briefly after their last server update so one missed nearby payload does not
/// cause immediate flicker, but they still disappear after a short grace window.
///
/// - Parameters:
///   - user: The nearby user whose visibility should be evaluated.
///   - now: The reference time used for the grace-window calculation.
/// - Returns: `true` when the user should still be shown in nearby UI.
func shouldRetainNearbyUser(_ user: UserLocation, now: Date = Date()) -> Bool {
    guard let lastSeenAt = user.lastSeenAt else { return true }
    return abs(lastSeenAt.timeIntervalSince(now)) <= NearbyLocationPolicy.offlineRetentionInterval
}

/// Builds a user-facing online status label for nearby UI.
///
/// The label is intentionally binary so the map and list views can communicate presence clearly
/// without exposing raw timestamps to the user.
///
/// - Parameters:
///   - user: The nearby user whose status text is needed.
///   - now: The reference time used for presence checks.
/// - Returns: `"Online"` when the user is fresh enough; otherwise `"Offline"`.
func nearbyPresenceLabel(for user: UserLocation, now: Date = Date()) -> String {
    isNearbyUserOnline(user, now: now) ? "Online" : "Offline"
}

/// Resolves the best display name for a nearby user card.
///
/// The resolver prefers explicit names, then falls back to cached contact data and safe user labels
/// so the nearby UI avoids leaking raw identifiers when better presentation data exists.
///
/// - Parameter user: The nearby user model to resolve.
/// - Returns: The display name that should be shown in the UI.
func resolvedUserDisplayName(_ user: UserLocation) -> String {
    DisplayNameResolver.resolve(displayName: user.displayName, email: user.email, phone: user.phone, userId: user.id)
}

/// Builds a deterministic seed for avatar rendering.
///
/// The seed prefers a user-facing name when available and falls back to stable identifiers so the
/// same nearby user keeps a consistent generated avatar between refreshes.
///
/// - Parameter user: The nearby user whose avatar seed is needed.
/// - Returns: A stable string used to derive avatar visuals.
func resolvedUserSeed(_ user: UserLocation) -> String {
    let name = resolvedUserDisplayName(user)
    return name == "User" ? (user.email ?? user.id) : name
}

/// Computes the live distance from the current device location to another user.
///
/// This helper uses the current persisted device location when available and falls back to the
/// server-provided distance when device coordinates are missing or unusable.
///
/// - Parameters:
///   - user: The nearby user whose distance should be measured.
///   - fallback: An optional distance supplied by the backend.
/// - Returns: The measured distance in meters, or the fallback distance when live math is unavailable.
func liveDistanceMeters(to user: UserLocation, fallback: Double? = nil) -> Double? {
    guard hasUsableCoordinate(latitude: user.latitude, longitude: user.longitude) else {
        return user.distanceMeters ?? fallback
    }
    guard let current = currentStoredDeviceLocation() else {
        return user.distanceMeters ?? fallback
    }

    let other = CLLocation(latitude: user.latitude, longitude: user.longitude)
    return current.distance(from: other)
}

/// Resolves the best distance value between two nearby users.
///
/// The function prefers direct coordinate-to-coordinate distance math, then falls back to the
/// device-relative distance path, and finally returns zero only when no usable distance exists.
///
/// - Parameters:
///   - centerUser: The reference user at the center of the nearby view.
///   - user: The other nearby user whose distance should be displayed.
/// - Returns: The resolved distance in meters for UI display.
func resolvedDistanceMeters(from centerUser: UserLocation, to user: UserLocation) -> Double {
    if let backendDistance = user.distanceMeters,
       backendDistance.isFinite,
       backendDistance >= 0 {
        return backendDistance
    }
    if hasUsableCoordinate(latitude: centerUser.latitude, longitude: centerUser.longitude),
       hasUsableCoordinate(latitude: user.latitude, longitude: user.longitude) {
        return calculateDistance(from: centerUser, to: user)
    }
    if let live = liveDistanceMeters(to: user, fallback: user.distanceMeters) {
        return live
    }
    return 0
}

/// Calculates geodesic distance between two nearby-user coordinates.
///
/// `CLLocation.distance(from:)` is used so the calculation stays in double precision and follows
/// Apple's location math instead of hand-rolled planar distance estimates.
///
/// - Parameters:
///   - from: The origin user.
///   - to: The destination user.
/// - Returns: The distance in meters between the two users.
func calculateDistance(from: UserLocation, to: UserLocation) -> Double {
    let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
    let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
    return loc1.distance(from: loc2)
}

/// Formats a meter value for nearby-user UI labels.
///
/// Distances under one kilometer stay in meters, while longer distances are compacted into a
/// one-decimal kilometer string for a cleaner list and profile presentation.
///
/// - Parameter meters: The raw distance in meters.
/// - Returns: A user-facing distance string such as `42 m` or `1.3 km`.
func homeFormatMeters(_ meters: Double) -> String {
    if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
    if meters < 10 { return String(format: "%.1f m", meters) }
    return String(format: "%.0f m", meters)
}

extension Notification.Name {
    static let _requestTagToggleFromMap = Notification.Name("requestTagToggleFromMap")
}
