import SwiftUI
import UIKit

enum CriticPalette {
    static let primary = Color(hex: 0x5E5CE6)
    static let primaryDark = Color(hex: 0x4D4BCF)
    static let primarySoft = Color(hex: 0xF1F0FF)
    static let accent = Color(hex: 0x8A63F8)
    static let background = Color(hex: 0xFCFCFD)
    static let surface = Color.white
    static let surfaceVariant = Color(hex: 0xF6F6F8)
    static let onSurface = Color(hex: 0x212533)
    static let onSurfaceMuted = Color(hex: 0x7B8190)
    static let outline = Color(hex: 0xE5E7EE)
    static let divider = Color(hex: 0xEAEAF0)
    static let success = Color(hex: 0x16A34A)
    static let warning = Color(hex: 0xF59E0B)
    static let error = Color(hex: 0xDC2626)
    static let info = Color(hex: 0x3B82F6)
    static let heroStart = Color(hex: 0xFAFAFC)
    static let heroEnd = Color(hex: 0xF4F4F8)
}

enum CriticSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 28
}

enum CriticRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let sheet: CGFloat = 26
    static let pill: CGFloat = 999
}

enum CriticTextRole {
    case display
    case pageTitle
    case sectionHeader
    case cardTitle
    case body
    case bodyStrong
    case label
    case caption
    case button
}

enum CriticTypography {
    static func font(_ role: CriticTextRole) -> Font {
        switch role {
        case .display:
            return .custom("Manrope-Bold", size: 26, relativeTo: .largeTitle)
        case .pageTitle:
            return .custom("Manrope-Bold", size: 20, relativeTo: .title2)
        case .sectionHeader:
            return .custom("Manrope-Bold", size: 15, relativeTo: .headline)
        case .cardTitle:
            return .custom("Manrope-Bold", size: 14, relativeTo: .headline)
        case .body:
            return .custom("Manrope-Regular", size: 14, relativeTo: .body)
        case .bodyStrong:
            return .custom("Manrope-SemiBold", size: 14, relativeTo: .body)
        case .label:
            return .custom("Manrope-Bold", size: 12, relativeTo: .caption)
        case .caption:
            return .custom("Manrope-Medium", size: 11.5, relativeTo: .caption)
        case .button:
            return .custom("Manrope-SemiBold", size: 14, relativeTo: .body)
        }
    }
}

extension Font {
    static func critic(_ role: CriticTextRole) -> Font {
        CriticTypography.font(role)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct CriticCardModifier: ViewModifier {
    var fill: Color = CriticPalette.surface
    var radius: CGFloat = CriticRadius.lg

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .shadow(color: Color(hex: 0x151A2D, alpha: 0.04), radius: 16, x: 0, y: 6)
            )
    }
}

extension View {
    func criticCard(fill: Color = CriticPalette.surface, radius: CGFloat = CriticRadius.lg) -> some View {
        modifier(CriticCardModifier(fill: fill, radius: radius))
    }

    @ViewBuilder
    func criticNavigationBarBackground(_ color: Color = CriticPalette.background) -> some View {
        if #available(iOS 16.0, *) {
            self
                .toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }
}

struct CriticFilledButtonStyle: ButtonStyle {
    var backgroundColor: Color = CriticPalette.primary
    var foregroundColor: Color = .white

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.critic(.button))
            .foregroundColor(isEnabled ? foregroundColor : CriticPalette.onSurfaceMuted)
            .frame(minHeight: 50)
            .padding(.horizontal, CriticSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isEnabled ? backgroundColor.opacity(configuration.isPressed ? 0.92 : 1) : CriticPalette.divider)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct CriticOutlinedButtonStyle: ButtonStyle {
    var foregroundColor: Color = CriticPalette.primary
    var backgroundColor: Color = CriticPalette.surface

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.critic(.button))
            .foregroundColor(isEnabled ? foregroundColor : CriticPalette.onSurfaceMuted)
            .frame(minHeight: 48)
            .padding(.horizontal, CriticSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isEnabled ? backgroundColor : CriticPalette.surfaceVariant)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isEnabled ? foregroundColor.opacity(0.22) : CriticPalette.outline, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct CriticSoftIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 36
    var iconSize: CGFloat = 18
    var opacity: Double = 0.1

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(color)
            )
    }
}

struct CriticPill: View {
    let icon: String
    let label: String
    var iconColor: Color = CriticPalette.primary
    var fill: Color = CriticPalette.surface

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(iconColor)
            Text(label)
                .font(.critic(.caption))
                .foregroundColor(CriticPalette.onSurface)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(fill)
                .overlay(Capsule(style: .continuous).stroke(CriticPalette.outline, lineWidth: 1))
        )
    }
}
