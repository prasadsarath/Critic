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
            isSimulated: user.isSimulated
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
                        .overlay(
                            ProgressView()
                                .controlSize(.small)
                                .tint(tintColor.opacity(0.8))
                        )
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
        isSimulated: Bool? = nil
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
    }
}

private enum NearbyLocationStorageKey {
    static let latitude = "lastKnownLatitude"
    static let longitude = "lastKnownLongitude"
}

private func hasUsableCoordinate(latitude: Double, longitude: Double) -> Bool {
    guard latitude.isFinite, longitude.isFinite else { return false }
    guard abs(latitude) <= 90, abs(longitude) <= 180 else { return false }
    return abs(latitude) > .ulpOfOne || abs(longitude) > .ulpOfOne
}

func currentStoredDeviceLocation() -> CLLocation? {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: NearbyLocationStorageKey.latitude) != nil,
          defaults.object(forKey: NearbyLocationStorageKey.longitude) != nil else {
        return nil
    }

    let latitude = defaults.double(forKey: NearbyLocationStorageKey.latitude)
    let longitude = defaults.double(forKey: NearbyLocationStorageKey.longitude)
    guard hasUsableCoordinate(latitude: latitude, longitude: longitude) else { return nil }
    return CLLocation(latitude: latitude, longitude: longitude)
}

func resolvedUserDisplayName(_ user: UserLocation) -> String {
    DisplayNameResolver.resolve(displayName: user.displayName, email: user.email, phone: user.phone, userId: user.id)
}

func resolvedUserSeed(_ user: UserLocation) -> String {
    let name = resolvedUserDisplayName(user)
    return name == "User" ? (user.email ?? user.id) : name
}

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

func resolvedDistanceMeters(from centerUser: UserLocation, to user: UserLocation) -> Double {
    if hasUsableCoordinate(latitude: centerUser.latitude, longitude: centerUser.longitude),
       hasUsableCoordinate(latitude: user.latitude, longitude: user.longitude) {
        return calculateDistance(from: centerUser, to: user)
    }
    if let live = liveDistanceMeters(to: user, fallback: user.distanceMeters) {
        return live
    }
    return 0
}

func calculateDistance(from: UserLocation, to: UserLocation) -> Double {
    let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
    let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
    return loc1.distance(from: loc2)
}

func homeFormatMeters(_ meters: Double) -> String {
    if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
    return String(format: "%.0f m", meters)
}

extension Notification.Name {
    static let _requestTagToggleFromMap = Notification.Name("requestTagToggleFromMap")
}
