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
    static func resolve(displayName: String?, userId: String?) -> String {
        if let name = preferredName(displayName, userId: userId) {
            if let validEmail = normalizedEmail(name),
               let local = validEmail.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first {
                return String(local)
            }
            return name
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
        }

        return "User"
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

    private static func preferredName(_ value: String?, userId: String?) -> String? {
        guard let trimmed = normalized(value) else { return nil }
        if let userId, trimmed == userId { return nil }
        if looksLikeOpaqueIdentifier(trimmed) { return nil }
        return trimmed
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("guest") == .orderedSame { return nil }
        if trimmed.caseInsensitiveCompare("guest@example.com") == .orderedSame { return nil }
        return trimmed
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        guard let trimmed = normalized(value), trimmed.contains("@") else { return nil }
        return trimmed
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
            .shadow(color: Color(hex: 0x151A2D, alpha: 0.03), radius: 8, x: 0, y: 3)
    }

    var body: some View {
        if let url = resolvedURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: size, height: size)
                        .background(avatarShell)
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
        .shadow(color: Color(hex: 0x151A2D, alpha: 0.03), radius: 8, x: 0, y: 3)
    }
}

struct UserLocation: Identifiable, Equatable, Hashable {
    let id: String
    let latitude: Double
    let longitude: Double
    let profileImageName: String
    let displayName: String?
    let profileUrl: String?

    init(
        id: String,
        latitude: Double,
        longitude: Double,
        profileImageName: String,
        displayName: String?,
        profileUrl: String? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.profileImageName = profileImageName
        self.displayName = displayName
        self.profileUrl = profileUrl
    }
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
