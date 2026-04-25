//
//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//

import SwiftUI
import Combine
import CoreLocation
import Foundation
import UIKit   // for UIViewController in AuthViewModel

// MARK: - List Background Hider (shared; NOT private)
struct ScrollBGHider: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

// MARK: - Flat Tab Bar
struct FlatTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs.indices, id: \.self) { idx in
                Button {
                    selectedTab = idx
                } label: {
                    Text(tabs[idx])
                        .font(.critic(.caption))
                        .foregroundColor(selectedTab == idx ? .white : Theme.subtleText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: CriticRadius.sm, style: .continuous)
                                .fill(selectedTab == idx ? Theme.tint : .clear)
                                .shadow(
                                    color: selectedTab == idx ? Theme.tint.opacity(0.22) : .clear,
                                    radius: 10,
                                    x: 0,
                                    y: 4
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: CriticRadius.md, style: .continuous)
                .fill(Theme.surfaceVariant)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.background)
    }
}

private struct UserMetaChip: View {
    let icon: String
    let label: String
    var color: Color = Theme.tint

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            Text(label)
                .font(.critic(.caption))
                .foregroundColor(CriticPalette.onSurface)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(CriticPalette.surface)
                .overlay(Capsule(style: .continuous).stroke(CriticPalette.outline, lineWidth: 1))
        )
    }
}

private struct UserActionButton: View {
    let title: String
    let icon: String
    let filled: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        if filled {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                    Text(title)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CriticFilledButtonStyle(backgroundColor: color))
        } else {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                    Text(title)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CriticOutlinedButtonStyle(foregroundColor: color))
        }
    }
}

// MARK: - Users List View (row tap → open profile; buttons unchanged)
struct UsersListView: View {
    let centerUser: UserLocation
    let allUsers: [UserLocation]

    let onWrite: (UserLocation) -> Void
    var onTagToggle: ((UserLocation) -> Void)? = nil
    var isTagged: ((UserLocation) -> Bool)? = nil
    let onOpenProfile: (UserLocation) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if allUsers.isEmpty {
                    VStack(spacing: 14) {
                        CriticSoftIcon(systemName: "person.3", color: Theme.info, size: 56, iconSize: 24)
                        Text("No nearby users yet")
                            .font(.critic(.pageTitle))
                            .foregroundColor(CriticPalette.onSurface)
                        Text("Pull to refresh or wait for the live socket to update.")
                            .font(.critic(.body))
                            .foregroundColor(CriticPalette.onSurfaceMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ForEach(allUsers) { user in
                        let displayName = resolvedUserDisplayName(user)
                        let distance = resolvedDistanceMeters(from: centerUser, to: user)
                        let tagged = isTagged?(user) ?? false
                        let presenceLabel = nearbyPresenceLabel(for: user)
                        let isOnline = isNearbyUserOnline(user)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                AvatarView(
                                    urlString: user.profileUrl,
                                    seed: resolvedUserSeed(user),
                                    fallbackSystemName: user.profileImageName,
                                    size: 48,
                                    backgroundColor: Theme.surface,
                                    tintColor: Theme.tint
                                )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(displayName)
                                        .font(.critic(.sectionHeader))
                                        .foregroundColor(CriticPalette.onSurface)
                                    HStack(spacing: 8) {
                                        UserMetaChip(icon: "location", label: "\(homeFormatMeters(distance)) away", color: Theme.tint)
                                        UserMetaChip(icon: "circle.fill", label: presenceLabel, color: isOnline ? Theme.success : Theme.subtleText)
                                        if tagged {
                                            UserMetaChip(icon: "tag", label: "Tagged", color: Theme.warning)
                                        }
                                    }
                                }

                                Spacer(minLength: 8)

                                Button {
                                    onOpenProfile(user)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(CriticPalette.onSurfaceMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenProfile(user) }

                            HStack(spacing: 10) {
                                if let onTagToggle {
                                    UserActionButton(
                                        title: tagged ? "Untag" : "Tag",
                                        icon: tagged ? "minus.circle" : "tag",
                                        filled: false,
                                        color: tagged ? Theme.error : Theme.tint,
                                        action: { onTagToggle(user) }
                                    )
                                }

                                UserActionButton(
                                    title: "Write",
                                    icon: "square.and.pencil",
                                    filled: true,
                                    color: Theme.tint,
                                    action: { onWrite(user) }
                                )
                            }
                        }
                        .padding(16)
                        .criticCard()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
    }
}

// MARK: - Relative User Map View (Info → profile; Write unchanged)
struct RelativeUserMap: View {
    let centerUser: UserLocation
    let otherUsers: [UserLocation]
    let onWrite: (UserLocation) -> Void
    let onOpenProfile: (UserLocation) -> Void

    @Binding var selectedUser: UserLocation?
    @Binding var selectedDistance: Double?

    @State private var scale: CGFloat = 20.0
    @GestureState private var gestureScale: CGFloat = 1.0
    let minZoom: CGFloat = 1.0
    let maxZoom: CGFloat = 70.0

    @State private var lastScreenPoint: [String: CGPoint] = [:]

    func convertToXY(from user: UserLocation) -> CGPoint {
        let metersPerDegreeLat = 111_000.0
        let metersPerDegreeLng = 111_320.0 * cos(centerUser.latitude * .pi / 180.0)
        let dx = (user.longitude - centerUser.longitude) * metersPerDegreeLng
        let dy = (user.latitude - centerUser.latitude) * metersPerDegreeLat
        return CGPoint(x: dx, y: -dy)
    }

    private func durationForMove(from: CGPoint, to: CGPoint) -> Double {
        let dx = to.x - from.x, dy = to.y - from.y
        let dist = sqrt(dx*dx + dy*dy)
        let baseSpeedPxPerSec: CGFloat = 40
        let minDur: Double = 0.45
        let maxDur: Double = 4.0
        let seconds = Double(dist / baseSpeedPxPerSec)
        return min(max(seconds, minDur), maxDur)
    }

    private func clearSelection() {
        selectedUser = nil
        selectedDistance = nil
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Theme.surface
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearSelection()
                    }

                ForEach([12.0, 7.0, 3.5], id: \.self) { ring in
                    Circle()
                        .fill(Theme.tint.opacity(ring == 3.5 ? 0.04 : 0.015))
                        .overlay(Circle().stroke(Theme.outline, lineWidth: 1))
                        .frame(width: CGFloat(ring * 2) * scale, height: CGFloat(ring * 2) * scale)
                        .position(center)
                }

                Circle()
                    .fill(Theme.tint)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Text("You")
                            .font(.critic(.caption))
                            .foregroundColor(.white)
                    )
                    .shadow(color: Color(hex: 0x232B45, alpha: 0.08), radius: 14, x: 0, y: 6)
                    .position(center)
                    .onTapGesture {
                        clearSelection()
                    }

                ForEach(otherUsers) { user in
                    let rel = convertToXY(from: user)
                    let currentPoint = CGPoint(x: center.x + rel.x * scale,
                                               y: center.y + rel.y * scale - 8)
                    let prevPoint = lastScreenPoint[user.id] ?? currentPoint
                    let animDur = durationForMove(from: prevPoint, to: currentPoint)
                    let d = resolvedDistanceMeters(from: centerUser, to: user)
                    let isSelected = selectedUser == user
                    let isOnline = isNearbyUserOnline(user)

                    ZStack(alignment: .top) {
                        VStack(spacing: 6) {
                            AvatarView(
                                urlString: user.profileUrl,
                                seed: resolvedUserSeed(user),
                                fallbackSystemName: user.profileImageName,
                                size: 40,
                                backgroundColor: Theme.surface,
                                tintColor: Theme.tint
                            )
                            .opacity(isOnline ? 1 : 0.62)
                            .overlay(Circle().stroke(isSelected ? Theme.tint : .clear, lineWidth: 2))
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(isOnline ? Theme.success : Theme.subtleText)
                                    .frame(width: 11, height: 11)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .offset(x: 1, y: 1)
                            }
                            .onTapGesture {
                                selectedUser = KnownUserDirectory.hydrated(user)
                                selectedDistance = d
                            }

                            Text("\(resolvedUserDisplayName(user)) · \(homeFormatMeters(d)) · \(nearbyPresenceLabel(for: user))")
                                .font(.critic(.caption))
                                .foregroundColor(isOnline ? CriticPalette.onSurface : CriticPalette.onSurfaceMuted)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(CriticPalette.surface.opacity(0.96))
                                        .overlay(Capsule(style: .continuous).stroke(CriticPalette.outline, lineWidth: 1))
                                )
                        }

                        if isSelected {
                            HStack(spacing: 8) {
                                Button {
                                    onWrite(user)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.pencil")
                                        Text("Write")
                                    }
                                    .font(.critic(.caption))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Capsule(style: .continuous).fill(Theme.tint))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    onOpenProfile(user)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle")
                                        Text("Info")
                                    }
                                    .font(.critic(.caption))
                                    .foregroundColor(Theme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Capsule(style: .continuous).fill(CriticPalette.surface))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    NavigationManager.shared.selectedUser = user
                                    NotificationCenter.default.post(name: ._requestTagToggleFromMap, object: user.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "tag")
                                        Text("Tag")
                                    }
                                    .font(.critic(.caption))
                                    .foregroundColor(Theme.warning)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Capsule(style: .continuous).fill(CriticPalette.surface))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .criticCard(radius: CriticRadius.md)
                            .offset(y: -74)
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .position(currentPoint)
                    .animation(.easeInOut(duration: animDur), value: currentPoint)
                    .onAppear { lastScreenPoint[user.id] = currentPoint }
                    .onChange(of: currentPoint) { newVal in lastScreenPoint[user.id] = newVal }
                }
            }
            .gesture(
                MagnificationGesture()
                    .updating($gestureScale) { value, state, _ in state = value }
                    .onEnded { value in
                        let newScale = scale * value
                        scale = min(max(newScale, minZoom), maxZoom)
                    }
            )
        }
    }
}

// MARK: - A tiny first-time connection HUD
private struct ConnectionHUD: View {
    enum Phase { case connecting, connectedLoading, ready }
    let phase: Phase
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            if phase == .ready {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.success)
            } else {
                ProgressView().progressViewStyle(CircularProgressViewStyle())
            }
            Text(text)
                .font(.critic(.caption))
                .foregroundColor(CriticPalette.onSurface)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule(style: .continuous).fill(Theme.surface))
        .overlay(Capsule(style: .continuous).stroke(Theme.outline, lineWidth: 1))
        .shadow(color: Color(hex: 0x151A2D, alpha: 0.04), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Tagged Tab UI (row tap → open profile)
struct TaggedUsersView: View {
    let tagged: [TaggedUser]
    let allUsers: [UserLocation]
    let onWrite: (UserLocation) -> Void
    let onUntag: (UserLocation) -> Void
    let onOpenProfile: (UserLocation) -> Void

    private func lookup(_ id: String) -> UserLocation {
        allUsers.first(where: { $0.id == id }) ??
        KnownUserDirectory.hydrated(UserLocation(
            id: id,
            latitude: 0,
            longitude: 0,
            profileImageName: "person.circle.fill",
            displayName: nil,
            profileUrl: nil
        ))
    }

    var body: some View {
        if tagged.isEmpty {
            VStack(spacing: 14) {
                CriticSoftIcon(systemName: "tag", color: Theme.warning, size: 56, iconSize: 24)
                Text("No active tagged users")
                    .font(.critic(.pageTitle))
                    .foregroundColor(CriticPalette.onSurface)
                Text("Tags expire in 24 hours. Tag someone from Ariel View or List to unlock the review window.")
                    .font(.critic(.body))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(tagged) { t in
                        let user = lookup(t.taggedUserId)
                        let displayName = resolvedUserDisplayName(user)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                AvatarView(
                                    urlString: user.profileUrl,
                                    seed: resolvedUserSeed(user),
                                    fallbackSystemName: user.profileImageName,
                                    size: 48,
                                    backgroundColor: Theme.surface,
                                    tintColor: Theme.tint
                                )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(displayName)
                                        .font(.critic(.sectionHeader))
                                        .foregroundColor(CriticPalette.onSurface)
                                    HStack(spacing: 8) {
                                        UserMetaChip(icon: "tag", label: "Tagged", color: Theme.warning)
                                        if let left = timeRemainingString(until: t.expiresAt) {
                                            UserMetaChip(icon: "clock", label: left, color: Theme.info)
                                        }
                                    }
                                }

                                Spacer(minLength: 8)

                                Button {
                                    onOpenProfile(user)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(CriticPalette.onSurfaceMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenProfile(user) }

                            HStack(spacing: 10) {
                                UserActionButton(
                                    title: "Write",
                                    icon: "square.and.pencil",
                                    filled: true,
                                    color: Theme.tint,
                                    action: { onWrite(user) }
                                )
                                UserActionButton(
                                    title: "Untag",
                                    icon: "minus.circle",
                                    filled: false,
                                    color: Theme.error,
                                    action: { onUntag(user) }
                                )
                            }
                        }
                        .padding(16)
                        .criticCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
        }
    }
}

// MARK: - Unified Alert Payload
fileprivate enum AlertType {
    case trace(UserLocation)
    case tagConfirm(UserLocation)
    case untagConfirm(UserLocation)
}

fileprivate struct AlertPayload: Identifiable {
    let id = UUID()
    let type: AlertType
}

private enum HomeTab: Hashable, CaseIterable {
    case home
    case list
    case posts
    case tagged
    case contacts
}

private struct HomeTabPresentation {
    let title: String
    let symbol: String
    let selectedSymbol: String
    let accent: UIColor
}

private extension HomeTab {
    var presentation: HomeTabPresentation {
        switch self {
        case .home:
            return .init(
                title: "Home",
                symbol: "house",
                selectedSymbol: "house.fill",
                accent: UIColor(Color(hex: 0x5B5CEB))
            )
        case .list:
            return .init(
                title: "List",
                symbol: "rectangle.grid.1x2",
                selectedSymbol: "rectangle.grid.1x2.fill",
                accent: UIColor(Color(hex: 0x0F766E))
            )
        case .posts:
            return .init(
                title: "Critics",
                symbol: "bubble.left.and.bubble.right",
                selectedSymbol: "bubble.left.and.bubble.right.fill",
                accent: UIColor(Color(hex: 0xF97316))
            )
        case .tagged:
            return .init(
                title: "Tagged",
                symbol: "tag",
                selectedSymbol: "tag.fill",
                accent: UIColor(CriticPalette.warning)
            )
        case .contacts:
            return .init(
                title: "Contacts",
                symbol: "person.2",
                selectedSymbol: "person.2.fill",
                accent: UIColor(Color(hex: 0x4F46E5))
            )
        }
    }
}

private struct GlossyDockBar: View {
    @Binding var selectedTab: HomeTab
    let postsUnreadCount: Int

    private var unreadBadgeText: String {
        postsUnreadCount > 99 ? "99+" : "\(postsUnreadCount)"
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                let presentation = tab.presentation
                let accent = Color(uiColor: presentation.accent)
                let isSelected = selectedTab == tab

                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 4) {
                            Image(systemName: isSelected ? presentation.selectedSymbol : presentation.symbol)
                                .font(.system(size: isSelected ? 17 : 16, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(accent.opacity(isSelected ? 1 : 0.75))
                                .frame(height: 18)

                            Text(presentation.title)
                                .font(isSelected ? .custom("Manrope-Bold", size: 10.5) : .custom("Manrope-Medium", size: 10.5))
                                .foregroundColor(isSelected ? CriticPalette.onSurface : CriticPalette.onSurfaceMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)

                        if tab == .posts, postsUnreadCount > 0 {
                            Text(unreadBadgeText)
                                .font(.custom("Manrope-Bold", size: 9.5))
                                .foregroundColor(.white)
                                .padding(.horizontal, postsUnreadCount > 9 ? 5 : 0)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(CriticPalette.error)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(CriticPalette.surface, lineWidth: 2)
                                )
                                .offset(x: 12, y: -6)
                                .accessibilityLabel("\(postsUnreadCount) unread critics")
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(isSelected ? accent.opacity(0.12) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(isSelected ? accent.opacity(0.18) : .clear, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(CriticPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(CriticPalette.outline, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color(hex: 0x111827, alpha: 0.05), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}

private struct PremiumHomeHeaderBar: View {
    let title: String
    let address: String
    let avatarURLString: String?
    let avatarSeed: String
    let onTap: () -> Void

    private var addressLabel: String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Locating…" : trimmed
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(
                    urlString: avatarURLString,
                    seed: avatarSeed,
                    fallbackSystemName: "person.crop.circle.fill",
                    size: 36,
                    backgroundColor: CriticPalette.surface,
                    tintColor: CriticPalette.primary
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.critic(.listTitle))
                        .foregroundColor(CriticPalette.onSurface)
                        .lineLimit(1)

                    Text(addressLabel)
                        .font(.critic(.caption))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

private struct PremiumHeaderRefreshButton: View {
    let action: () -> Void
    var isRefreshing: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(CriticPalette.primary)
                .frame(width: 30, height: 30)
                .rotationEffect(.degrees(isRefreshing ? 180 : 0))
                .animation(.easeInOut(duration: 0.35), value: isRefreshing)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CriticPalette.primarySoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(CriticPalette.primary.opacity(0.12), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Refresh nearby users")
    }
}

// MARK: - Home View
struct HomeView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var navigationManager = NavigationManager.shared
    @State private var profileDestUser: UserLocation? = nil

    // Driven by WebSocket
    @State private var userLocations: [UserLocation] = []
    @StateObject private var socket = AWSWebSocketClient(config: AppConfig.socketConfig)

    // UI update stream
    @State private var nearbyCancellable: AnyCancellable?

    // keep sim ticking
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var selectedUser: UserLocation?
    @State private var selectedDistance: Double?
    @State private var isRefreshAnimating = false
    @State private var selectedTab: HomeTab = .home
    @State private var postsFeedTab: Int = 0

    // Live inbox count
    @StateObject private var inboxVM = InboxCountViewModel()

    // ✅ Tagging VM
    @StateObject private var tagVM = TagViewModel()
    @StateObject private var meVM = MeProfileViewModel()

    // Reactive user name shown in top bar
    @AppStorage("userName") private var storedUserName: String = ""
    @AppStorage("userEmail") private var storedUserEmail: String = ""
    @AppStorage("userProfileUrl") private var storedUserProfileURL: String = ""
    private var displayName: String {
        DisplayNameResolver.homeHeaderName(
            storedName: storedUserName,
            userId: UserDefaults.standard.string(forKey: "userId"),
            email: storedUserEmail
        )
    }
    private var currentProfileURL: String? {
        let trimmed = storedUserProfileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private var headerTitle: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Hey" : "Hey \(trimmed)"
    }

    // First-time connection HUD state
    @State private var showBootHUD: Bool = true
    @State private var bootPhase: ConnectionHUD.Phase = .connecting
    @State private var bootPollCancellable: AnyCancellable?
    @State private var didShowReadyOnce = false

    // View/app lifecycle
    @Environment(\.scenePhase) private var scenePhase
    @State private var isHomeActive: Bool = false
    @State private var isSocketConnectPending: Bool = false
    @State private var lastNearbySyncAt: Date = .distantPast
    @State private var lastNearbySyncCoordinate: CLLocationCoordinate2D?
    @State private var pendingNearbyRefresh: PendingNearbyRefresh?
    @State private var tagToggleObserver: NSObjectProtocol?

    // ✅ Single active alert only
    @State private var activeAlert: AlertPayload? = nil

    private struct PendingNearbyRefresh {
        let force: Bool
        let promptForLocation: Bool
        let reason: String
    }

    private let nearbyRefreshCooldown: TimeInterval = 0.25
    private let nearbyRefreshDistanceThreshold: CLLocationDistance = 0.25
    private var isRunningPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().isHidden = true
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    private func tabIcon(for tab: HomeTab) -> some View {
        let presentation = tab.presentation
        let isSelected = selectedTab == tab
        let configuration = UIImage.SymbolConfiguration(
            pointSize: isSelected ? 18 : 17,
            weight: isSelected ? .semibold : .medium,
            scale: .small
        )
        let symbolName = isSelected ? presentation.selectedSymbol : presentation.symbol
        let alpha = isSelected ? 1.0 : 0.72
        let image = UIImage(systemName: symbolName, withConfiguration: configuration)?
            .withTintColor(presentation.accent.withAlphaComponent(alpha), renderingMode: .alwaysOriginal)

        return Image(uiImage: image ?? UIImage())
            .renderingMode(.original)
    }

    private func tabLabel(for tab: HomeTab) -> some View {
        let title = tab.presentation.title
        return VStack(spacing: 3) {
            tabIcon(for: tab)
            Text(title)
        }
    }

    private func currentUserId() -> String? {
        let uid = UserDefaults.standard.string(forKey: "userId")
        if uid == nil { print("⚠️ [Home] Missing userId. User not fully signed in yet.") }
        return uid
    }

    private var centerUser: UserLocation {
        if let coord = locationManager.effectiveCoordinate {
            return UserLocation(
                id: UserDefaults.standard.string(forKey: "userId") ?? "You",
                latitude: coord.latitude,
                longitude: coord.longitude,
                profileImageName: "person.fill",
                displayName: "You",
                email: storedUserEmail,
                profileUrl: currentProfileURL
            )
        } else if let first = userLocations.first {
            return UserLocation(
                id: UserDefaults.standard.string(forKey: "userId") ?? "You",
                latitude: first.latitude,
                longitude: first.longitude,
                profileImageName: "person.fill",
                displayName: "You",
                email: storedUserEmail,
                profileUrl: currentProfileURL
            )
        } else {
            return UserLocation(
                id: UserDefaults.standard.string(forKey: "userId") ?? "You",
                latitude: 0,
                longitude: 0,
                profileImageName: "person.fill",
                displayName: "You",
                email: storedUserEmail,
                profileUrl: currentProfileURL
            )
        }
    }
    private var allUsers: [UserLocation] {
        let now = Date()
        return userLocations.filter { isNearbyUserOnline($0, now: now) }
    }
    private var nearbyUsers: [UserLocation] {
        let now = Date()
        return allUsers.filter {
            isNearbyUserOnline($0, now: now) &&
            resolvedDistanceMeters(from: centerUser, to: $0) <= 5_000
        }
    }
    private var activeUsers: [UserLocation] {
        nearbyUsers.isEmpty ? allUsers : nearbyUsers
    }
    private var onlineActiveUsers: [UserLocation] {
        let now = Date()
        return activeUsers.filter { isNearbyUserOnline($0, now: now) }
    }
    private var isLocationDrivenTab: Bool {
        selectedTab == .home || selectedTab == .list
    }

    private var statusText: String {
        switch socket.state {
        case .connected:  return "Connected"
        case .connecting: return "Connecting…"
        case .closing:    return "Closing…"
        case .closed:     return "Closed"
        case .failed(let m): return "Failed: \(m)"
        case .disconnected:  return "Disconnected"
        }
    }
    private var statusColor: Color {
        switch socket.state {
        case .connected:  return .green
        case .connecting: return .orange
        default:          return .gray
        }
    }

    // MARK: - reflect profile url safely (no 33 errors)
    private func extractProfileURL(from anyValue: Any) -> String? {
        let mirror = Mirror(reflecting: anyValue)
        for child in mirror.children {
            switch child.label {
            case "profile_url", "profileUrl", "avatarUrl", "avatarURL":
                return child.value as? String
            default:
                continue
            }
        }
        return nil
    }

    private func hydrateUser(_ user: UserLocation) -> UserLocation {
        KnownUserDirectory.hydrated(user)
    }

    private func mergeNearbyUsers(
        current _: [UserLocation],
        incoming: [UserLocation],
        now: Date = Date()
    ) -> [UserLocation] {
        return incoming.sorted { lhs, rhs in
            let lhsOnline = isNearbyUserOnline(lhs, now: now)
            let rhsOnline = isNearbyUserOnline(rhs, now: now)
            if lhsOnline != rhsOnline {
                return lhsOnline && !rhsOnline
            }

            let lhsDistance = resolvedDistanceMeters(from: centerUser, to: lhs)
            let rhsDistance = resolvedDistanceMeters(from: centerUser, to: rhs)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            return resolvedUserDisplayName(lhs).localizedCaseInsensitiveCompare(resolvedUserDisplayName(rhs)) == .orderedAscending
        }
    }

    private func resolvedDistance(for user: UserLocation) -> Double {
        resolvedDistanceMeters(from: centerUser, to: hydrateUser(user))
    }

    // MARK: - Open profile (centralized)
    private func openProfile(for user: UserLocation) {
        let hydratedUser = hydrateUser(user)
        if navigationManager.showProfile, profileDestUser == hydratedUser { return }
        profileDestUser = hydratedUser
        NavigationManager.shared.selectedUser = hydratedUser
        NavigationManager.shared.selectedDistance = resolvedDistance(for: hydratedUser)
        NavigationManager.shared.showProfile = true
        print(
            "[Nav] Open profile userId=\(hydratedUser.id) " +
            "name=\(hydratedUser.displayName ?? "nil") " +
            "email=\(hydratedUser.email ?? "nil")"
        )
    }

    // MARK: - WebSocket orchestration
    private func connectSocketIfReady() {
        guard let uid = currentUserId() else {
            print("[WS] connect skipped: missing userId")
            return
        }
        guard OIDCAuthManager.shared.hasAuthState else {
            print("[WS] connect skipped: missing auth state")
            return
        }
        guard !isSocketConnectPending else {
            return
        }
        if socket.state.isConnected || socket.state == .connecting {
            return
        }
        isSocketConnectPending = true
        Task {
            do {
                let idToken = try await OIDCAuthManager.shared.getIDToken()
                await MainActor.run {
                    self.isSocketConnectPending = false
                    guard self.isHomeActive else { return }
                    guard self.currentUserId() == uid else { return }
                    guard OIDCAuthManager.shared.hasAuthState else { return }
                    if self.socket.state.isConnected || self.socket.state == .connecting {
                        return
                    }
                    print("[WS] Connecting for userId=\(uid)")
                    self.socket.connect(headers: ["Authorization": "Bearer \(idToken)"])
                }
            } catch {
                await MainActor.run {
                    self.isSocketConnectPending = false
                    print("[WS] connect skipped: missing id token (\(error.localizedDescription))")
                }
            }
        }
    }

    private func disconnectSocket(reason: String) {
        if socket.state.isConnected || socket.state == .connecting {
            print("[WS] Disconnecting (\(reason))")
        }
        isSocketConnectPending = false
        pendingNearbyRefresh = nil
        let userId = currentUserId()
        let shouldUseBackgroundTask = reason == "background" || reason == "logout" || reason == "re-login"
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

        if shouldUseBackgroundTask {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "CriticClearPresence") {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
        }

        socket.disconnect(gracefulClearUserId: userId) {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        userLocations = []
    }

    private func resolveProfileDest() -> UserLocation? {
        guard let dest = profileDestUser else { return nil }
        let me = UserDefaults.standard.string(forKey: "userId")
        return (dest.id == me) ? nil : dest
    }

    private var statusStrip: some View {
        Group {
            if #available(iOS 16.0, *) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        statusConnectionPill
                        statusNearbyPill
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 10) {
                        statusConnectionPill
                        statusNearbyPill
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                HStack(spacing: 12) {
                    statusConnectionPill
                    statusNearbyPill
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.background)
    }

    private var statusConnectionPill: some View {
        CriticPill(
            icon: "circle.fill",
            label: statusText,
            iconColor: socket.state == .connected ? Theme.success : socket.state == .connecting ? Theme.warning : Theme.subtleText
        )
    }

    private var statusNearbyPill: some View {
        let onlineCount = onlineActiveUsers.count
        return CriticPill(
            icon: "person.2",
            label: "\(onlineCount) \(onlineCount == 1 ? "person" : "people") online in range",
            iconColor: Theme.tint
        )
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PremiumHomeHeaderBar(
                    title: headerTitle,
                    address: locationManager.currentAddress,
                    avatarURLString: currentProfileURL,
                    avatarSeed: UserDefaults.standard.string(forKey: "userId") ?? displayName
                ) {
                    let selfUser = UserLocation(
                        id: UserDefaults.standard.string(forKey: "userId") ?? "me",
                        latitude: centerUser.latitude,
                        longitude: centerUser.longitude,
                        profileImageName: "person.circle.fill",
                        displayName: displayName,
                        profileUrl: currentProfileURL
                    )
                    openProfile(for: selfUser)
                }

                if selectedTab == .home || selectedTab == .list {
                    PremiumHeaderRefreshButton(
                        action: {
                            refreshNearbyUsers()
                        },
                        isRefreshing: isRefreshAnimating
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, selectedTab == .posts ? 2 : 6)

            if isLocationDrivenTab {
                statusStrip
            }

            if selectedTab == .posts {
                FlatTabBar2(selectedTab: $postsFeedTab, tabs: ["Received", "Posted"])
                    .padding(.bottom, 4)
            }
        }
        .background(Theme.background)
    }

    private var shouldHideRootNavigationBar: Bool {
        true
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .home:
            RelativeUserMap(
                centerUser: centerUser,
                otherUsers: activeUsers,
                onWrite: { user in attemptWrite(user: user) },
                onOpenProfile: { user in openProfile(for: user) },
                selectedUser: $selectedUser,
                selectedDistance: $selectedDistance
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)

        case .list:
            UsersListView(
                centerUser: centerUser,
                allUsers: activeUsers,
                onWrite: { user in attemptWrite(user: user) },
                onTagToggle: { user in handleTagToggle(for: user) },
                isTagged: { user in tagVM.isTagged(user.id) },
                onOpenProfile: { user in openProfile(for: user) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)

        case .posts:
            ReviewFeedView(tabSelection: $postsFeedTab, showNavigationTitle: false, showsTabBar: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CriticPalette.background)

        case .tagged:
            TaggedUsersView(
                tagged: tagVM.tagged,
                allUsers: allUsers,
                onWrite: { attemptWrite(user: $0) },
                onUntag: { user in handleTagToggle(for: user) },
                onOpenProfile: { user in openProfile(for: user) }
            )
            .background(Theme.background)
            .refreshable {
                guard let uid = currentUserId() else { return }
                await tagVM.refresh(for: uid)
            }

        case .contacts:
            ContactsView(
                vm: contactsVM,
                onClose: { selectedTab = .home }
            ) { userId, displayName in
                KnownUserDirectory.remember(userId: userId, displayName: displayName, email: nil, phone: nil, profileUrl: nil)
                let u = UserLocation(
                    id: userId,
                    latitude: centerUser.latitude,
                    longitude: centerUser.longitude,
                    profileImageName: "person.circle.fill",
                    displayName: DisplayNameResolver.resolve(
                        displayName: displayName ?? KnownUserDirectory.name(for: userId),
                        email: KnownUserDirectory.email(for: userId),
                        phone: KnownUserDirectory.phone(for: userId),
                        userId: userId
                    ),
                    profileUrl: nil
                )
                attemptWrite(user: u)
            }
            .background(Theme.background)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !navigationManager.showProfile && !navigationManager.showWritePost {
                        topBar
                    }

                    selectedTabContent
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !navigationManager.showProfile && !navigationManager.showWritePost {
                            GlossyDockBar(selectedTab: $selectedTab, postsUnreadCount: inboxVM.count)
                        }
                    }
                }

                NavigationLink(
                    destination:
                        ProfileView(otherUser: resolveProfileDest())
                            .id(profileDestUser?.id ?? "self")
                            .navigationBarBackButtonHidden(false),
                    isActive: $navigationManager.showProfile
                ) { EmptyView() }

                NavigationLink(
                    destination: WriteReviewView().navigationBarBackButtonHidden(false),
                    isActive: $navigationManager.showWritePost
                ) { EmptyView() }
            }
                .navigationBarHidden(shouldHideRootNavigationBar)
                .task {
                    guard !isRunningPreview else { return }
                    await meVM.loadIfNeeded()
                }

                .onAppear {
                    guard !isRunningPreview else {
                        isHomeActive = false
                        showBootHUD = false
                        didShowReadyOnce = true
                        if storedUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            storedUserName = "Preview"
                        }
                        return
                    }

                    isHomeActive = true

                if storedUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let name = UserDefaults.standard.string(forKey: "userName"), !name.isEmpty {
                    storedUserName = name
                }

                OIDCAuthManager.shared.printUserSnapshot(tag: "Home.onAppear(before refresh)")
                OIDCAuthManager.shared.refreshIfNeeded { _ in
                    if let latest = UserDefaults.standard.string(forKey: "userName"),
                       !latest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        storedUserName = latest
                    }
                    OIDCAuthManager.shared.printUserSnapshot(tag: "Home.onAppear(after refresh)")
                }

                connectSocketIfReady()
                syncLocationMonitoring(for: selectedTab)
                pushAndFetchNearby(force: true, reason: "home appear")
                Task { await contactsVM.bootstrap() }
                KnownUserDirectory.rememberCurrentUserFromDefaults()

                if let uid = currentUserId() {
                    inboxVM.start(userId: uid, every: 15)
                    Task { await tagVM.refresh(for: uid) }
                }

                bootPollCancellable = Timer.publish(every: 0.25, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        guard showBootHUD else { return }
                        switch socket.state {
                        case .connecting: bootPhase = .connecting
                        case .connected:
                            if !didShowReadyOnce { bootPhase = .connectedLoading }
                        default: break
                        }
                    }

                if nearbyCancellable == nil {
                    nearbyCancellable = socket.$nearbyUsers
                        .sink { users in
                            let receivedAt = Date()
                            KnownUserDirectory.rememberCurrentUserFromDefaults()

                            let incomingUsers = users.map { item -> UserLocation in
                                let avatar = extractProfileURL(from: item) ?? KnownUserDirectory.profileUrl(for: item.userId)
                                let cachedEmail = item.email ?? KnownUserDirectory.email(for: item.userId)
                                let cachedPhone = item.phone ?? KnownUserDirectory.phone(for: item.userId)
                                KnownUserDirectory.remember(
                                    userId: item.userId,
                                    displayName: item.name,
                                    email: cachedEmail,
                                    phone: cachedPhone,
                                    profileUrl: avatar
                                )

                                return UserLocation(
                                    id: item.userId,
                                    latitude: item.lat,
                                    longitude: item.lon,
                                    profileImageName: "person.circle.fill",
                                    displayName: DisplayNameResolver.resolve(
                                        displayName: item.name ?? KnownUserDirectory.name(for: item.userId),
                                        email: cachedEmail,
                                        phone: cachedPhone,
                                        userId: item.userId
                                    ),
                                    email: cachedEmail,
                                    phone: cachedPhone,
                                    profileUrl: avatar,
                                    distanceMeters: item.distanceM,
                                    isSimulated: item.isSimulated,
                                    lastSeenAt: parseNearbyPresenceDate(item.updatedAt) ?? receivedAt
                                )
                            }
                            let mergedUsers = self.mergeNearbyUsers(
                                current: self.userLocations,
                                incoming: incomingUsers,
                                now: receivedAt
                            )
                            self.userLocations = mergedUsers

                            if let currentSelection = self.selectedUser,
                               let refreshed = mergedUsers.first(where: { $0.id == currentSelection.id }) {
                                let hydrated = self.hydrateUser(refreshed)
                                self.selectedUser = hydrated
                                self.selectedDistance = self.resolvedDistance(for: hydrated)
                            }

                            if let navSelection = NavigationManager.shared.selectedUser,
                               let refreshed = mergedUsers.first(where: { $0.id == navSelection.id }) {
                                let hydrated = self.hydrateUser(refreshed)
                                NavigationManager.shared.selectedUser = hydrated
                                NavigationManager.shared.selectedDistance = self.resolvedDistance(for: hydrated)
                                if self.profileDestUser?.id == hydrated.id {
                                    self.profileDestUser = hydrated
                                }
                            }

                            if !didShowReadyOnce {
                                didShowReadyOnce = true
                                bootPhase = .ready
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    withAnimation(.easeInOut(duration: 0.25)) { showBootHUD = false }
                                    bootPollCancellable?.cancel()
                                    bootPollCancellable = nil
                                }
                            }
                    }
                }

                if tagToggleObserver == nil {
                    tagToggleObserver = NotificationCenter.default.addObserver(
                        forName: ._requestTagToggleFromMap,
                        object: nil,
                        queue: .main
                    ) { notif in
                        guard let targetId = notif.object as? String,
                              let u = self.userLocations.first(where: { $0.id == targetId }) else { return }
                        self.handleTagToggle(for: u)
                    }
                }
            }

            .onReceive(NotificationCenter.default.publisher(for: .didLogin)) { _ in
                if let latest = UserDefaults.standard.string(forKey: "userName"),
                   !latest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    storedUserName = latest
                }
                OIDCAuthManager.shared.printUserSnapshot(tag: "didLogin")
                if let uid = currentUserId() {
                    inboxVM.start(userId: uid, every: 15)
                }
                disconnectSocket(reason: "re-login")
                connectSocketIfReady()
                pushAndFetchNearby(force: true, reason: "didLogin")
            }

            .onReceive(NotificationCenter.default.publisher(for: .didLogout)) { _ in
                inboxVM.stop()
                disconnectSocket(reason: "logout")
            }

            .onReceive(NotificationCenter.default.publisher(for: .jumpToPosted)) { _ in
                selectedTab = .posts
            }

            .onDisappear {
                isHomeActive = false
                locationManager.stopUpdating()
                nearbyCancellable?.cancel()
                nearbyCancellable = nil
                inboxVM.stop()
                bootPollCancellable?.cancel()
                bootPollCancellable = nil
                if scenePhase != .active {
                    disconnectSocket(reason: "view disappear")
                }
                if let observer = tagToggleObserver {
                    NotificationCenter.default.removeObserver(observer)
                    tagToggleObserver = nil
                }
            }

            .onChange(of: scenePhase) { phase in
                guard isHomeActive else { return }
                switch phase {
                case .active:
                    OIDCAuthManager.shared.printUserSnapshot(tag: "scene.active")
                    if let latest = UserDefaults.standard.string(forKey: "userName"),
                       !latest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        storedUserName = latest
                    }
                    syncLocationMonitoring(for: selectedTab)
                    connectSocketIfReady()
                    pushAndFetchNearby(force: true, reason: "scene active")
                case .background, .inactive:
                    locationManager.stopUpdating()
                    disconnectSocket(reason: "background")
                @unknown default: break
                }
            }

            .onReceive(tick) { _ in
                guard isHomeActive, isLocationDrivenTab else { return }
                pushAndFetchNearby(reason: "periodic tick")
            }

            .onReceive(locationManager.$currentLocation.compactMap { $0 }) { _ in
                guard isHomeActive else { return }
                pushAndFetchNearby(reason: "location update")
            }

            .onReceive(socket.$state.removeDuplicates()) { state in
                guard isHomeActive else { return }
                guard case .connected = state, let pending = pendingNearbyRefresh else { return }
                pushAndFetchNearby(
                    force: pending.force,
                    promptForLocation: pending.promptForLocation,
                    reason: "\(pending.reason) (socket opened)"
                )
            }

            .alert(item: $activeAlert) { payload in
                switch payload.type {
                case .trace(let user):
                    return Alert(
                        title: Text("You are more traceable"),
                        message: Text("Only \(nearbyUsers.count) users are nearby. You may be easier to trace. This is a disclaimer — you can continue to write and post."),
                        primaryButton: .cancel(Text("Cancel"), action: { activeAlert = nil }),
                        secondaryButton: .default(Text("Continue"), action: {
                            let hydrated = hydrateUser(user)
                            NavigationManager.shared.selectedUser = hydrated
                            NavigationManager.shared.selectedDistance = resolvedDistance(for: hydrated)
                            NavigationManager.shared.showWritePost = true
                            activeAlert = nil
                        })
                    )
                case .tagConfirm(let user):
                    return Alert(
                        title: Text("Tag \(resolvedUserDisplayName(user))?"),
                        message: Text("You’re tagging this user. You can post your review in the next 24 hours."),
                        primaryButton: .cancel(Text("Cancel"), action: { activeAlert = nil }),
                        secondaryButton: .default(Text("Proceed"), action: {
                            confirmTagging(user: user); activeAlert = nil
                        })
                    )
                case .untagConfirm(let user):
                    return Alert(
                        title: Text("Untag \(resolvedUserDisplayName(user))?"),
                        message: Text("Are you sure you want to untag this user?"),
                        primaryButton: .cancel(Text("Cancel"), action: { activeAlert = nil }),
                        secondaryButton: .destructive(Text("Untag"), action: {
                            confirmUntag(user: user); activeAlert = nil
                        })
                    )
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: selectedTab) { tab in
            syncLocationMonitoring(for: tab)
            if tab == .home || tab == .list {
                pushAndFetchNearby(reason: "tab change")
            }
            if tab == .tagged {
                guard let uid = currentUserId() else { return }
                Task { await tagVM.refresh(for: uid) }
            }
        }
    }

    @StateObject private var contactsVM = ContactsViewModel()

    private func attemptWrite(user: UserLocation) {
        let hydrated = hydrateUser(user)
        let contactsUsingApp = contactsVM.registered.count

        if contactsUsingApp > 0 && contactsUsingApp < 5 {
            activeAlert = AlertPayload(type: .trace(hydrated)); return
        }
        if contactsUsingApp == 0 && nearbyUsers.count < 11 {
            activeAlert = AlertPayload(type: .trace(hydrated)); return
        }

        NavigationManager.shared.selectedUser = hydrated
        NavigationManager.shared.selectedDistance = resolvedDistance(for: hydrated)
        NavigationManager.shared.showWritePost = true
    }

    private func refreshNearbyUsers() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRefreshAnimating = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRefreshAnimating = false
            }
        }
        locationManager.requestAccessIfNeeded()
        pushAndFetchNearby(force: true, reason: "manual refresh")
    }

    private func syncLocationMonitoring(for tab: HomeTab) {
        if tab == .home || tab == .list {
            locationManager.requestAccessIfNeeded()
        } else {
            locationManager.stopUpdating()
        }
    }

    /// Pushes the current nearby-ready location to the socket and refreshes the nearby list.
    ///
    /// The function enforces the existing cooldown and movement thresholds, falls back to prompting
    /// for location access when needed, and then sends the same websocket payload contract already
    /// used by the backend for `updateLocation` and `getNearbyUsers`.
    ///
    /// - Parameters:
    ///   - force: Skips cooldown and movement gating when `true`.
    ///   - promptForLocation: Requests location access when no usable coordinate is currently available.
    ///   - reason: A short debug label describing why the refresh was triggered.
    private func pushAndFetchNearby(force: Bool = false, promptForLocation: Bool = false, reason: String) {
        guard socket.state.isConnected else {
            print("[WS] Nearby refresh pending (\(reason)): socket state=\(socket.state.shortText)")
            pendingNearbyRefresh = PendingNearbyRefresh(
                force: force,
                promptForLocation: promptForLocation,
                reason: reason
            )
            connectSocketIfReady()
            return
        }
        guard let uid = UserDefaults.standard.string(forKey: "userId") else {
            print("[WS] Nearby refresh skipped (\(reason)): missing userId")
            return
        }
        guard let coord = locationManager.effectiveCoordinate else {
            print("[WS] Nearby refresh skipped (\(reason)): missing effective coordinate")
            if promptForLocation {
                locationManager.requestAccessIfNeeded()
            }
            return
        }

        if !force {
            let now = Date()
            let didCoolDown = now.timeIntervalSince(lastNearbySyncAt) >= nearbyRefreshCooldown
            let didMoveEnough: Bool
            if let lastCoord = lastNearbySyncCoordinate {
                let currentLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let previousLocation = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                didMoveEnough = currentLocation.distance(from: previousLocation) >= nearbyRefreshDistanceThreshold
            } else {
                didMoveEnough = true
            }

            guard didCoolDown || didMoveEnough else {
                print("[WS] Nearby refresh skipped (\(reason)) due to cooldown")
                return
            }
        }

        pendingNearbyRefresh = nil
        lastNearbySyncAt = Date()
        lastNearbySyncCoordinate = coord

        let lat = coord.latitude
        let lon = coord.longitude
        let currentName = UserDefaults.standard.string(forKey: "userName")
        let currentEmail = UserDefaults.standard.string(forKey: "userEmail")
        let currentProfileURL = UserDefaults.standard.string(forKey: "userProfileUrl")
        print("[WS] Location updated and nearby refresh sent (\(reason)) lat=\(lat) lon=\(lon)")

        socket.sendUpdateLocation(
            userId: uid,
            latitude: lat,
            longitude: lon,
            displayName: currentName,
            email: currentEmail,
            profileUrl: currentProfileURL
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.socket.sendGetNearbyUsers(
                userId: uid,
                latitude: lat,
                longitude: lon,
                radiusMeters: 15,
                displayName: currentName,
                email: currentEmail,
                profileUrl: currentProfileURL
            )
        }

        if force {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                guard self.isHomeActive, self.socket.state.isConnected else { return }
                self.socket.sendGetNearbyUsers(
                    userId: uid,
                    latitude: lat,
                    longitude: lon,
                    radiusMeters: 15,
                    displayName: currentName,
                    email: currentEmail,
                    profileUrl: currentProfileURL
                )
            }
        }
    }

    private func handleTagToggle(for user: UserLocation) {
        let isAlready = tagVM.isTagged(user.id)
        activeAlert = AlertPayload(type: isAlready ? .untagConfirm(user) : .tagConfirm(user))
    }

    private func confirmTagging(user: UserLocation) {
        guard let uid = UserDefaults.standard.string(forKey: "userId") else { return }
        Task {
            let ok = await tagVM.tag(userId: uid, targetId: user.id)
            if ok {
                selectedTab = .tagged
                await tagVM.refresh(for: uid)
            }
        }
    }

    private func confirmUntag(user: UserLocation) {
        guard let uid = UserDefaults.standard.string(forKey: "userId") else { return }
        Task {
            let ok = await tagVM.untag(userId: uid, targetId: user.id)
            if ok, selectedTab == .tagged {
                await tagVM.refresh(for: uid)
            }
        }
    }
}

// MARK: - Preview
private struct AuthViewPreviewSnapshot: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PremiumHomeHeaderBar(
                    title: "Hey Preview",
                    address: "San Francisco, CA",
                    avatarURLString: nil,
                    avatarSeed: "preview"
                ) {}

                PremiumHeaderRefreshButton(
                    action: {},
                    isRefreshing: false
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Group {
                if #available(iOS 16.0, *) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            CriticPill(icon: "circle.fill", label: "Connected", iconColor: Theme.success)
                            CriticPill(icon: "person.2", label: "3 people in range", iconColor: Theme.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        VStack(alignment: .leading, spacing: 10) {
                            CriticPill(icon: "circle.fill", label: "Connected", iconColor: Theme.success)
                            CriticPill(icon: "person.2", label: "3 people in range", iconColor: Theme.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    HStack(spacing: 12) {
                        CriticPill(icon: "circle.fill", label: "Connected", iconColor: Theme.success)
                        CriticPill(icon: "person.2", label: "3 people in range", iconColor: Theme.tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Spacer()
        }
        .background(Theme.background)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        AuthViewPreviewSnapshot()
            .preferredColorScheme(.light)
    }
}
