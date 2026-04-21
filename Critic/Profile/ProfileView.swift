//
//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//

import SwiftUI
import UIKit
import PhotosUI

/// Pass `otherUser: nil` to show **your own** profile (Edit/Settings/Logout/Invite).
/// Pass `otherUser: UserLocation` to show an **external** profile (details + Write only).
struct ProfileView: View {
    // If nil → self profile; else → external
    let otherUser: UserLocation?

    // Persisted (for self)
    @AppStorage("userName") private var userName: String = "Guest"
    @AppStorage("userEmail") private var userEmail: String = "guest@example.com"
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false

    // Local UI state for self
    @State private var profileImage: Image = Image(systemName: "person.circle.fill")
    @State private var hasCustomProfileImage: Bool = false
    @State private var name: String
    @State private var email: String
    @State private var bio: String = ""

    // Navigation / sheets / alerts
    @State private var pushEdit = false
    @State private var pushSettings = false

    @StateObject private var meVM = MeProfileViewModel()

    private let inviteLink = AppExternalLinks.inviteLanding

    init(otherUser: UserLocation? = nil) {
        self.otherUser = otherUser
        let initialName  = UserDefaults.standard.string(forKey: "userName") ?? "Guest"
        let initialEmail = UserDefaults.standard.string(forKey: "userEmail") ?? "guest@example.com"
        _name  = State(initialValue: initialName)
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        Group {
            if let u = otherUser {
                ExternalProfileContent(user: u)
            } else {
                SelfProfileContent(
                    profileImage: $profileImage,
                    hasCustomProfileImage: $hasCustomProfileImage,
                    name: $name,
                    email: $email,
                    bio: $bio,
                    meVM: meVM,
                    pushEdit: $pushEdit,
                    pushSettings: $pushSettings,
                    inviteLink: inviteLink
                )
            }
        }
        // IMPORTANT: Do NOT toggle NavigationManager.shared.showProfile here.
        // Doing so during a push to Edit/Settings causes the Home NavigationLink to deactivate,
        // popping back to Home immediately. The NavigationLink in Home will manage its own state.
    }
}

// MARK: - Self Profile Content
private struct SelfProfileContent: View {
    private enum ActiveSheet: Int, Identifiable {
        case invite

        var id: Int { rawValue }
    }

    private enum ActiveAlert: Int, Identifiable {
        case logout

        var id: Int { rawValue }
    }

    @Binding var profileImage: Image
    @Binding var hasCustomProfileImage: Bool
    @Binding var name: String
    @Binding var email: String
    @Binding var bio: String
    @Environment(\.dismiss) private var dismiss

    @AppStorage("userName") private var userName: String = "Guest"
    @AppStorage("userEmail") private var userEmail: String = "guest@example.com"
    @AppStorage("userProfileUrl") private var userProfileUrl: String = ""

    @ObservedObject var meVM: MeProfileViewModel

    @State private var activeSheet: ActiveSheet?
    @State private var activeAlert: ActiveAlert?
    @Binding var pushEdit: Bool
    @Binding var pushSettings: Bool

    let inviteLink: URL

    private var navigationTitleText: String {
        normalizedName(name) ?? "Profile"
    }

    private var storedProfileURL: String? {
        let value = userProfileUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                CriticDetailHeader(title: navigationTitleText) {
                    dismiss()
                }

                VStack(spacing: 18) {
                    Text("How others see you")
                        .font(.critic(.bodyStrong))
                        .foregroundColor(CriticPalette.onSurface)

                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if hasCustomProfileImage {
                                profileImage
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 108, height: 108)
                            } else if let storedProfileURL {
                                AvatarView(
                                    urlString: storedProfileURL,
                                    seed: nil,
                                    fallbackSystemName: "person.circle.fill",
                                    size: 108,
                                    backgroundColor: CriticPalette.surface,
                                    tintColor: CriticPalette.primary
                                )
                            } else {
                                ProfileWatermarkAvatar(size: 108)
                            }
                        }
                        .clipShape(Circle())

                        Button(action: { pushEdit = true }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(CriticPalette.primary))
                        }
                        .offset(x: 6, y: 6)
                    }

                    Text("When you post, you will appear as.")
                        .font(.footnote)
                        .foregroundColor(CriticPalette.onSurface)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(name)
                        .font(.critic(.display))
                        .foregroundColor(CriticPalette.onSurface)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .criticCard()
                .padding(.horizontal, 16)
                .padding(.top, 12)

                profileDetailsCard()

                VStack(spacing: 0) {
                    ProfileMenuRow(icon: "pencil", text: "Edit Profile", action: { pushEdit = true })
                    Divider().padding(.leading, 56)
                    ProfileMenuRow(icon: "gearshape", text: "Settings", action: { pushSettings = true })
                    Divider().padding(.leading, 56)
                    ProfileMenuRow(icon: "person.2.fill", text: "Invite a friend", action: { activeSheet = .invite })
                    Divider()
                    ProfileMenuRow(
                        icon: "rectangle.portrait.and.arrow.forward",
                        text: "Logout",
                        textColor: CriticPalette.error,
                        iconColor: CriticPalette.error,
                        action: { activeAlert = .logout }
                    )
                }
                .criticCard()
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

                NavigationLink(
                    destination:
                        EditProfileView(
                            name: name,
                            email: email,
                            bio: bio,
                            image: profileImage,
                            remoteAvatarURL: storedProfileURL,
                            showsCustomImage: hasCustomProfileImage,
                            onSave: { newName, newEmail, newBio, newImage in
                                let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                                var resolvedProfileURL = storedProfileURL

                                if let newImage {
                                    let compressedData: Data?
                                    let contentType: String

                                    if let jpegData = newImage.jpegData(compressionQuality: 0.85) {
                                        compressedData = jpegData
                                        contentType = "image/jpeg"
                                    } else if let pngData = newImage.pngData() {
                                        compressedData = pngData
                                        contentType = "image/png"
                                    } else {
                                        throw APIError.invalidRequest
                                    }

                                    guard let imageData = compressedData else {
                                        throw APIError.invalidRequest
                                    }

                                    let uploadTarget = try await UsersProfileService.requestAvatarUploadTarget(contentType: contentType)
                                    try await UsersProfileService.uploadAvatarData(imageData, using: uploadTarget)
                                    resolvedProfileURL = uploadTarget.fileURL
                                }

                                let updatedProfile = try await UsersProfileService.updateCurrentUser(
                                    name: trimmedName,
                                    bio: newBio,
                                    profileURL: resolvedProfileURL
                                )

                                self.name = trimmedName
                                self.email = newEmail
                                self.userName = trimmedName
                                self.userEmail = newEmail
                                self.bio = newBio
                                if let newImage {
                                    self.profileImage = Image(uiImage: newImage)
                                    self.hasCustomProfileImage = true
                                }
                                if resolvedProfileURL != nil {
                                    self.userProfileUrl = resolvedProfileURL ?? ""
                                }
                                self.meVM.user = UsersProfileService.meUser(from: updatedProfile)
                                await self.meVM.load()
                            }
                        )
                        .navigationBarBackButtonHidden(false),
                    isActive: $pushEdit
                ) { EmptyView() }

                NavigationLink(
                    destination: SettingsView(
                        onDeleteAccountConfirmed: { performDeletedAccountExit() }
                    )
                        .navigationBarBackButtonHidden(false),
                    isActive: $pushSettings
                ) { EmptyView() }
            }
            .padding(.top, 8)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .onAppear { syncFromStorage() }
        .onChange(of: userName) { _ in syncFromStorage() }
        .onChange(of: userEmail) { _ in syncFromStorage() }
        .onChange(of: meVM.user) { _ in applyProfileData() }
        .onChange(of: meVM.identity) { _ in applyProfileData() }
        .task { await meVM.loadIfNeeded() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .invite:
                InviteFriendsSheet(inviteURL: inviteLink)
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .logout:
                return Alert(
                    title: Text("Are you sure you want to logout?"),
                    message: Text("You will need to sign in again to access your account."),
                    primaryButton: .cancel(Text("Cancel")),
                    secondaryButton: .destructive(Text("Yes"), action: performLogout)
                )
            }
        }
    }

    private func syncFromStorage() {
        let storedName = normalizedName(userName)
        if let storedName {
            self.name = storedName
        } else if let emailName = nameFromEmail(userEmail) {
            self.name = emailName
        } else {
            self.name = "Guest"
        }

        self.email = userEmail
    }

    private func applyProfileData() {
        if let newName = normalizedName(meVM.user?.name) {
            applyName(newName)
        } else if let identityName = normalizedName(meVM.identity?.name) {
            applyName(identityName)
        } else if let identityFullName = normalizedName(
            [meVM.identity?.givenName, meVM.identity?.familyName]
                .compactMap { normalizedName($0) }
                .joined(separator: " ")
        ) {
            applyName(identityFullName)
        } else if let nickname = normalizedName(meVM.user?.nickname) {
            applyName(nickname)
        } else if let identityNickname = normalizedName(meVM.identity?.nickname) {
            applyName(identityNickname)
        } else if let preferredUsername = normalizedName(meVM.identity?.preferredUsername) {
            applyName(preferredUsername)
        } else if let cognito = normalizedName(meVM.identity?.cognitoUsername) {
            applyName(cognito)
        } else if let emailName = nameFromEmail(meVM.identity?.email ?? userEmail) {
            applyName(emailName)
        }

        if let newEmail = meVM.identity?.email, !newEmail.isEmpty {
            email = newEmail
            userEmail = newEmail
        }

        if let newBio = meVM.user?.bio {
            bio = newBio
        }
    }

    private func applyName(_ newName: String) {
        name = newName
        userName = newName
    }

    private func performLogout() {
        resetLocalSessionState()
        OIDCAuthManager.shared.signOut(kind: .standardLogout)
    }

    private func performDeletedAccountExit() {
        resetLocalSessionState()
        OIDCAuthManager.shared.completeLocalLogout(kind: .accountDeletion)
    }

    private func resetLocalSessionState() {
        profileImage = Image(systemName: "person.circle.fill")
        hasCustomProfileImage = false
        bio = ""
        userProfileUrl = ""
        NavigationManager.shared.showInbox = false
        NavigationManager.shared.showWritePost = false
        NavigationManager.shared.showProfile = false
    }

    private func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("guest") == .orderedSame { return nil }
        return trimmed
    }

    private func nameFromEmail(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("guest@example.com") == .orderedSame { return nil }
        let local = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first
        return normalizedName(local.map(String.init))
    }

    @ViewBuilder
    private func profileDetailsCard() -> some View {
        let rows = profileRows()
        if !rows.isEmpty || meVM.isLoading || meVM.errorText != nil {
            VStack(spacing: 0) {
                HStack {
                    Text("Profile Details")
                        .font(.critic(.cardTitle))
                        .foregroundColor(CriticPalette.onSurface)
                    Spacer()
                    if meVM.isLoading {
                        ProgressView().scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                if let err = meVM.errorText {
                    Text(err)
                        .font(.critic(.caption))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                ForEach(rows.indices, id: \.self) { idx in
                    let row = rows[idx]
                    ProfileInfoRow(title: row.title, value: row.value)
                    if idx < rows.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.bottom, 12)
            .criticCard()
            .padding(.horizontal, 16)
        }
    }

    private func profileRows() -> [(title: String, value: String)] {
        var rows: [(String, String)] = []

        let preferredUsername = trimmedValue(meVM.identity?.preferredUsername)

        if let preferredUsername {
            rows.append(("Username", preferredUsername))
        }
        if let nickname = trimmedValue(meVM.user?.nickname ?? meVM.identity?.nickname),
           nickname.caseInsensitiveCompare(preferredUsername ?? "") != .orderedSame {
            rows.append(("Nickname", nickname))
        }
        if let givenName = trimmedValue(meVM.identity?.givenName) {
            rows.append(("First Name", givenName))
        }
        if let familyName = trimmedValue(meVM.identity?.familyName) {
            rows.append(("Last Name", familyName))
        }
        if let phoneNumber = trimmedValue(meVM.identity?.phoneNumber) {
            rows.append(("Phone", phoneNumber))
        }
        if let emailAddress = trimmedValue(meVM.identity?.email ?? email) {
            rows.append(("Email", emailAddress))
        }
        if let emailVerified = meVM.identity?.emailVerified {
            rows.append(("Email Verified", emailVerified ? "Yes" : "No"))
        }
        if let phoneVerified = meVM.identity?.phoneNumberVerified {
            rows.append(("Phone Verified", phoneVerified ? "Yes" : "No"))
        }
        if let profession = meVM.user?.profession {
            rows.append(("Profession", profession))
        }

        let resolvedBio = (meVM.user?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolvedBio.isEmpty {
            rows.append(("Bio", resolvedBio))
        }

        return rows
    }

    private func trimmedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ProfileWatermarkAvatar: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(CriticPalette.surface)

            Circle()
                .stroke(CriticPalette.outline, lineWidth: 1)

            Image("StartupHero")
                .resizable()
                .scaledToFit()
                .padding(size * 0.2)
                .opacity(0.3)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Default profile logo")
    }
}

// MARK: - External Profile Content (common UI used everywhere)
private struct ExternalProfileContent: View {
    let user: UserLocation
    @Environment(\.dismiss) private var dismiss
    @State private var refreshedUser: UserLocation?
    @State private var fetchedProfile: UsersTableProfile?

    private var displayedUser: UserLocation {
        refreshedUser ?? KnownUserDirectory.hydrated(user)
    }

    private var resolvedDisplayName: String {
        resolvedUserDisplayName(displayedUser)
    }

    private var navigationTitleText: String {
        let trimmed = resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "User" ? "Profile" : trimmed
    }

    private var subtitleText: String {
        if let memberSinceText {
            return memberSinceText
        }
        return displayedUser.isSimulated == true ? "Simulated nearby user" : "Nearby user"
    }

    private var memberSinceText: String? {
        guard let raw = fetchedProfile?.createdAt ?? fetchedProfile?.updatedAt else { return nil }
        return "User since \(humanReadableProfileDate(raw))"
    }

    private var distanceText: String? {
        guard let meters = liveDistanceMeters(to: displayedUser, fallback: displayedUser.distanceMeters) else {
            return nil
        }
        return "\(homeFormatMeters(meters)) away"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                CriticDetailHeader(title: navigationTitleText) {
                    dismiss()
                }

                VStack(spacing: 16) {
                    AvatarView(
                        urlString: displayedUser.profileUrl,
                        seed: resolvedUserSeed(displayedUser),
                        fallbackSystemName: displayedUser.profileImageName,
                        size: 108,
                        backgroundColor: CriticPalette.surface,
                        tintColor: CriticPalette.primary
                    )

                    Text(resolvedDisplayName)
                        .font(.critic(.display))
                        .foregroundColor(CriticPalette.onSurface)
                        .multilineTextAlignment(.center)

                    Text(subtitleText)
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .multilineTextAlignment(.center)

                    if let distanceText {
                        Text(distanceText)
                            .font(.critic(.bodyStrong))
                            .foregroundColor(CriticPalette.primary)
                    }
                }
                .padding(20)
                .criticCard()

                VStack(spacing: 0) {
                    ProfileInfoRow(title: "Distance", value: distanceText ?? "Updating location…")
                    if let memberSinceText {
                        Divider().padding(.leading, 16)
                        ProfileInfoRow(title: "User Since", value: memberSinceText.replacingOccurrences(of: "User since ", with: ""))
                    }
                    Divider().padding(.leading, 16)
                    ProfileInfoRow(
                        title: "Status",
                        value: displayedUser.isSimulated == true ? "Simulated nearby user" : "Live nearby user"
                    )
                }
                .criticCard()

                Button {
                    NavigationManager.shared.selectedUser = displayedUser
                    NavigationManager.shared.selectedDistance = liveDistanceMeters(
                        to: displayedUser,
                        fallback: displayedUser.distanceMeters
                    )
                    NavigationManager.shared.showWritePost = true
                } label: {
                    Text("Write")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CriticFilledButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .task(id: user.id) {
            await refreshFromUsersTableIfPossible()
        }
    }

    private func refreshFromUsersTableIfPossible() async {
        do {
            print("[ExternalProfile] request users_get for userId=\(user.id)")
            let profile = try await UsersProfileService.fetchUser(userId: user.id)
            let merged = UsersProfileService.merge(profile, onto: user)
            print(
                "[ExternalProfile] users_get success requestedUserId=\(user.id) " +
                "resolvedUserId=\(merged.id) name=\(merged.displayName ?? "nil") " +
                "email=\(merged.email ?? "nil")"
            )
            fetchedProfile = profile
            refreshedUser = merged
            if NavigationManager.shared.selectedUser?.id == merged.id {
                NavigationManager.shared.selectedUser = merged
                NavigationManager.shared.selectedDistance = liveDistanceMeters(
                    to: merged,
                    fallback: merged.distanceMeters
                )
            }
        } catch {
            print("[ExternalProfile] users_get failed for \(user.id): \(error.localizedDescription)")
        }
    }

    private func humanReadableProfileDate(_ raw: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackParser = ISO8601DateFormatter()
        fallbackParser.formatOptions = [.withInternetDateTime]

        let date = parser.date(from: raw) ?? fallbackParser.date(from: raw)
        guard let date else { return raw }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Profile Menu Row
struct ProfileMenuRow: View {
    var icon: String
    var text: String
    var textColor: Color = CriticPalette.onSurface
    var iconColor: Color = CriticPalette.primary
    var showsChevron: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                CriticSoftIcon(
                    systemName: icon,
                    color: iconColor,
                    size: 38,
                    iconSize: 18,
                    opacity: icon == "rectangle.portrait.and.arrow.forward" ? 0.10 : 0.08
                )
                Text(text)
                    .font(.critic(.listTitle))
                    .foregroundColor(textColor)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .padding(.vertical, 15)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Info Row
struct ProfileInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.critic(.sectionHeader))
                .foregroundColor(CriticPalette.onSurface)
                .frame(width: 120, alignment: .leading)
            Spacer(minLength: 8)
            Text(value)
                .font(.critic(.body))
                .foregroundColor(CriticPalette.onSurfaceMuted)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct CriticSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.critic(.sectionHeader))
                .foregroundColor(CriticPalette.onSurfaceMuted)
                .tracking(1.1)
                .padding(.horizontal, 6)

            VStack(spacing: 0) {
                content
            }
            .criticCard()
        }
    }
}

private struct CriticSettingsRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    var titleColor: Color = CriticPalette.onSurface
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            CriticSoftIcon(
                systemName: icon,
                color: iconColor,
                size: 50,
                iconSize: 21,
                opacity: 0.12
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.critic(.listTitle))
                    .foregroundColor(titleColor)
                Text(subtitle)
                    .font(.critic(.body))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

private struct CriticSettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            CriticSoftIcon(
                systemName: icon,
                color: iconColor,
                size: 50,
                iconSize: 21,
                opacity: 0.12
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.critic(.listTitle))
                    .foregroundColor(CriticPalette.onSurface)
                Text(subtitle)
                    .font(.critic(.body))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(CriticPalette.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }
}

private struct CriticFormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var textInputAutocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.critic(.sectionHeader))
                .foregroundColor(CriticPalette.onSurfaceMuted)

            TextField(placeholder, text: $text)
                .font(.critic(.listTitle))
                .foregroundColor(CriticPalette.onSurface)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(textInputAutocapitalization)
                .disableAutocorrection(true)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CriticPalette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(CriticPalette.outline, lineWidth: 1)
                        )
                )
        }
    }
}

private struct CriticLockedValueField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.critic(.sectionHeader))
                .foregroundColor(CriticPalette.onSurfaceMuted)

            HStack(spacing: 12) {
                Text(value)
                    .font(.critic(.listTitle))
                    .foregroundColor(CriticPalette.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "lock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CriticPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CriticPalette.outline, lineWidth: 1)
                    )
            )
        }
    }
}

private struct CriticMultilineField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.critic(.sectionHeader))
                .foregroundColor(CriticPalette.onSurfaceMuted)

            ZStack(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $text)
                    .font(.critic(.body))
                    .foregroundColor(CriticPalette.onSurface)
                    .modifier(ScrollBGHider())
                    .frame(minHeight: 120)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CriticPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CriticPalette.outline, lineWidth: 1)
                    )
            )
        }
    }
}

private struct CriticTermsConsentRow: View {
    @Binding var isAccepted: Bool

    var body: some View {
        Button {
            isAccepted.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(CriticPalette.primary)

                Text(isAccepted ? "I accept the Terms & Conditions." : "Accept the Terms & Conditions to continue.")
                    .font(.critic(.body))
                    .foregroundColor(CriticPalette.onSurface)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Profile View (iOS 15 safe)
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State var name: String
    @State var email: String
    @State var bio: String
    @State var image: Image
    let remoteAvatarURL: String?
    let showsCustomImage: Bool
    var onSave: (_ name: String, _ email: String, _ bio: String, _ newImage: UIImage?) async throws -> Void

    @State private var showPhotoSheet = false
    @State private var pickedUIImage: UIImage?
    @State private var hasAcceptedGuidelines = true
    @State private var isSaving = false
    @State private var saveErrorText: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasAcceptedGuidelines
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let pickedUIImage {
            Image(uiImage: pickedUIImage)
                .resizable()
                .scaledToFill()
                .frame(width: 116, height: 116)
                .clipShape(Circle())
        } else if showsCustomImage {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 116, height: 116)
                .clipShape(Circle())
        } else if let remoteAvatarURL, !remoteAvatarURL.isEmpty {
            AvatarView(
                urlString: remoteAvatarURL,
                seed: name.isEmpty ? email : name,
                fallbackSystemName: "person.crop.circle.fill",
                size: 116,
                backgroundColor: CriticPalette.surface,
                tintColor: CriticPalette.primary
            )
        } else {
            ProfileWatermarkAvatar(size: 116)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                CriticDetailHeader(title: "Edit profile") {
                    dismiss()
                }

                VStack(spacing: 18) {
                    ZStack(alignment: .bottomTrailing) {
                        avatarPreview

                        Button(action: { showPhotoSheet = true }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(CriticPalette.primary))
                        }
                        .offset(x: 8, y: 8)
                    }

                    Text("Add a clear face photo - this builds trust.")
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .multilineTextAlignment(.center)

                    Button {
                        showPhotoSheet = true
                    } label: {
                        Label("Try another avatar", systemImage: "arrow.triangle.2.circlepath")
                            .font(.critic(.pageTitle))
                            .foregroundColor(CriticPalette.primary)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .criticCard()

                VStack(spacing: 16) {
                    CriticFormField(
                        title: "Full name *",
                        placeholder: "Enter your full name",
                        text: $name,
                        textContentType: .name,
                        textInputAutocapitalization: .words
                    )
                    CriticLockedValueField(title: "Email *", value: email)
                    CriticMultilineField(
                        title: "Bio",
                        placeholder: "Tell people what kind of feedback you like to receive.",
                        text: $bio
                    )
                }
                .padding(20)
                .criticCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Safety & guidelines")
                        .font(.critic(.display))
                        .foregroundColor(CriticPalette.onSurface)

                    Text("Critic is based on real people and trust. Please agree to our community rules before you continue.")
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    CriticTermsConsentRow(isAccepted: $hasAcceptedGuidelines)
                }
                .padding(20)
                .criticCard()

                Button {
                    Task {
                        await saveChanges()
                    }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save changes")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(CriticFilledButtonStyle())
                .disabled(!canSave || isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $showPhotoSheet) {
            PhotoPicker(image: $pickedUIImage)
                .onChange(of: pickedUIImage) { newValue in
                    if let ui = newValue { image = Image(uiImage: ui) }
                }
        }
        .alert("Couldn't save profile", isPresented: Binding(
            get: { saveErrorText != nil },
            set: { if !$0 { saveErrorText = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorText = nil }
        } message: {
            Text(saveErrorText ?? "Please try again.")
        }
    }

    private func saveChanges() async {
        guard canSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await onSave(name, email, bio, pickedUIImage)
            dismiss()
        } catch {
            saveErrorText = error.localizedDescription
        }
    }
}

// MARK: - Invite Friends Bottom Sheet (iOS 15 safe)
struct InviteFriendsSheet: View {
    let inviteURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    private var isWhatsAppInstalled: Bool { AppDetector.canOpen("whatsapp://send") }
    private var isFacebookInstalled: Bool { AppDetector.canOpen("fb://") }
    private var isSnapchatInstalled: Bool { AppDetector.canOpen("snapchat://") }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    CriticDetailHeader(title: "Invite a friend") {
                        dismiss()
                    }

                    VStack(spacing: 8) {
                        Text("Share your invite link using your favorite app.")
                            .font(.critic(.body))
                            .foregroundColor(CriticPalette.onSurfaceMuted)
                            .multilineTextAlignment(.center)

                        Text(inviteURL.absoluteString)
                            .font(.critic(.caption))
                            .foregroundColor(CriticPalette.primary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .criticCard()

                    VStack(spacing: 12) {
                        if isWhatsAppInstalled {
                            InviteRow(title: "WhatsApp", systemIcon: "message.fill") {
                                let text = "Hey! Join me on Critic: \(inviteURL.absoluteString)"
                                let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                if let url = URL(string: "whatsapp://send?text=\(encoded)") {
                                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                }
                                dismiss()
                            }
                        }

                        if isFacebookInstalled {
                            InviteRow(title: "Facebook", systemIcon: "f.square.fill") {
                                showShareSheet = true
                            }
                        }

                        if isSnapchatInstalled {
                            InviteRow(title: "Snapchat", systemIcon: "bolt.fill") {
                                showShareSheet = true
                            }
                        }

                        InviteRow(title: "More…", systemIcon: "square.and.arrow.up") {
                            showShareSheet = true
                        }
                    }
                    .padding(20)
                    .criticCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(CriticPalette.background.ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .navigationBarHidden(true)
        }
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: ["Join me on Critic!", inviteURL])
        }
    }
}

struct InviteRow: View {
    let title: String
    let systemIcon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemIcon)
                    .frame(width: 28, height: 28)
                    .foregroundColor(CriticPalette.primary)
                Text(title)
                    .font(.critic(.listTitle))
                    .foregroundColor(CriticPalette.onSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(CriticPalette.onSurfaceMuted)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(CriticPalette.surfaceVariant)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings View (iOS 15 safe)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notifications_enabled") private var notificationsEnabled = true

    var onDeleteAccountConfirmed: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                CriticDetailHeader(title: "Settings") {
                    dismiss()
                }

                CriticSettingsSection(title: "Preferences") {
                    CriticSettingsToggleRow(
                        icon: "bell.badge.fill",
                        title: "Notifications",
                        subtitle: "Mentions and activity alerts",
                        iconColor: CriticPalette.warning,
                        isOn: $notificationsEnabled
                    )

                    Divider().padding(.leading, 80)

                    Button {
                        AppReviewRequester.requestReview()
                    } label: {
                        CriticSettingsRowLabel(
                            icon: "star.fill",
                            title: "Rate App",
                            subtitle: "Tell us how Critic is working for you",
                            iconColor: CriticPalette.warning
                        )
                    }
                    .buttonStyle(.plain)
                }

                CriticSettingsSection(title: "Account") {
                    NavigationLink {
                        PrivacyVisibilityView()
                    } label: {
                        CriticSettingsRowLabel(
                            icon: "lock.fill",
                            title: "Privacy & Visibility",
                            subtitle: "Control what others can see about you",
                            iconColor: CriticPalette.primary
                        )
                    }
                    .buttonStyle(.plain)
                }

                CriticSettingsSection(title: "Legal") {
                    Button {
                        UIApplication.shared.open(AppExternalLinks.terms)
                    } label: {
                        CriticSettingsRowLabel(
                            icon: "doc.text.fill",
                            title: "Terms & Conditions",
                            subtitle: "Review the community rules",
                            iconColor: CriticPalette.primary
                        )
                    }
                    .buttonStyle(.plain)
                }

                CriticSettingsSection(title: "Support") {
                    NavigationLink {
                        HelpFeedbackView()
                    } label: {
                        CriticSettingsRowLabel(
                            icon: "bubble.right.fill",
                            title: "Help & Feedback",
                            subtitle: "Send product suggestions or bug reports",
                            iconColor: CriticPalette.accent
                        )
                    }
                    .buttonStyle(.plain)
                }

                CriticSettingsSection(title: "Account") {
                    NavigationLink {
                        DeleteAccountView(onAccountDeleted: onDeleteAccountConfirmed)
                    } label: {
                        CriticSettingsRowLabel(
                            icon: "trash.fill",
                            title: "Delete Account",
                            subtitle: "Permanently delete your account",
                            iconColor: CriticPalette.error,
                            titleColor: CriticPalette.error,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .environment(\.colorScheme, .light)
    }
}

struct DeleteAccountView: View {
    private enum ActiveResultAlert: Identifiable {
        case error(String)
        case pending(String)

        var id: String {
            switch self {
            case .error(let message):
                return "error:\(message)"
            case .pending(let message):
                return "pending:\(message)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let onAccountDeleted: () -> Void

    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var activeResultAlert: ActiveResultAlert?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                CriticDetailHeader(title: "Delete Account") {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("This permanently deletes your Critic account and associated app data.")
                        .font(.critic(.display))
                        .foregroundColor(CriticPalette.onSurface)

                    Text("Information we are legally required to keep may be retained for compliance, fraud prevention, or dispute handling. We do not offer a retain or deactivate option instead of deletion.")
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .criticCard(fill: CriticPalette.surface)

                VStack(alignment: .leading, spacing: 14) {
                    Text("What happens next")
                        .font(.critic(.pageTitle))
                        .foregroundColor(CriticPalette.onSurface)

                    deletionBullet("Your account is permanently deleted. We do not keep a user-facing retain or deactivate state.")
                    deletionBullet("Your sign-in access is blocked so you can’t log back in with the deleted account.")
                    deletionBullet("Your Critic profile and associated app data are deleted, except where retention is legally required.")
                    deletionBullet("If backend processing takes additional time, the app will tell you before signing you out.")
                }
                .padding(20)
                .criticCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text("This action can’t be undone.")
                        .font(.critic(.bodyStrong))
                        .foregroundColor(CriticPalette.error)

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Group {
                            if isDeleting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Delete account")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .buttonStyle(CriticFilledButtonStyle(backgroundColor: CriticPalette.error))
                    .disabled(isDeleting)
                }
                .padding(20)
                .criticCard(fill: CriticPalette.surfaceVariant)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .environment(\.colorScheme, .light)
        .confirmationDialog("Delete this account?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your account and associated app data, except information we are legally required to retain.")
        }
        .alert(item: $activeResultAlert) { alert in
            switch alert {
            case .error(let message):
                return Alert(
                    title: Text("Couldn't Delete Account"),
                    message: Text(message),
                    dismissButton: .cancel(Text("OK"))
                )
            case .pending(let message):
                return Alert(
                    title: Text("Account Deletion Requested"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"), action: onAccountDeleted)
                )
            }
        }
    }

    @ViewBuilder
    private func deletionBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(CriticPalette.error)
                .padding(.top, 6)

            Text(text)
                .font(.critic(.body))
                .foregroundColor(CriticPalette.onSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            let response = try await UsersProfileService.deleteCurrentUser()
            let status = response.normalizedStatus
            let message = response.normalizedMessage

            if response.ok == false || isDeleteFailureStatus(status) {
                activeResultAlert = .error(
                    message ?? "The server couldn't delete your account right now."
                )
                return
            }

            if isDeletePendingStatus(status) {
                let pendingText = message
                    ?? "Your deletion request was accepted and will finish shortly."
                activeResultAlert = .pending(pendingText)
                return
            }

            onAccountDeleted()
        } catch {
            activeResultAlert = .error(accountDeletionErrorText(from: error))
        }
    }

    private func accountDeletionErrorText(from error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .statusCode(_, let data):
                if let serverMessage = accountDeletionServerMessage(from: data) {
                    return serverMessage
                }
                return "The server couldn't delete your account right now."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func isDeletePendingStatus(_ status: String?) -> Bool {
        guard let status else { return false }
        switch status {
        case "accepted", "in_progress", "pending", "processing", "queued", "scheduled":
            return true
        default:
            return false
        }
    }

    private func isDeleteFailureStatus(_ status: String?) -> Bool {
        guard let status else { return false }
        switch status {
        case "denied", "error", "failed", "failure", "rejected":
            return true
        default:
            return false
        }
    }

    private func accountDeletionServerMessage(from data: Data?) -> String? {
        guard let data else { return nil }
        if let decoded = try? JSONDecoder().decode(AccountDeletionResponse.self, from: data),
           let message = decoded.normalizedMessage {
            return message
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

struct HelpFeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var message: String = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var successMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                CriticDetailHeader(title: "Help & Feedback") {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("FEEDBACK")
                        .font(.critic(.sectionHeader))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .tracking(1.1)
                        .padding(.horizontal, 6)

                    VStack(alignment: .leading, spacing: 18) {
                        FeedbackComposerField(text: $message)

                        Button {
                            Task { await submitFeedback() }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(CriticPalette.primary)

                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Send")
                                        .font(.critic(.button))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(height: 64)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting || trimmedMessage.isEmpty)
                        .opacity(isSubmitting || trimmedMessage.isEmpty ? 0.7 : 1)

                        Text(successMessage ?? "We usually review feedback within a few days.")
                            .font(.critic(.body))
                            .foregroundColor(successMessage == nil ? CriticPalette.onSurfaceMuted : CriticPalette.success)

                        NavigationLink {
                            FeedbackSubmissionsView()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 21, weight: .semibold))
                                Text("View My Submissions")
                                    .font(.critic(.button))
                            }
                            .foregroundColor(CriticPalette.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .criticCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .environment(\.colorScheme, .light)
        .alert(
            "Couldn't Send Feedback",
            isPresented: Binding(
                get: { submitError != nil },
                set: { if !$0 { submitError = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { submitError = nil }
            },
            message: {
                Text(submitError ?? "Please try again.")
            }
        )
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func submitFeedback() async {
        guard !trimmedMessage.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let submission = try await FeedbackService.submit(message: trimmedMessage)
            let statusText = submission?.statusText ?? "Submitted"
            print("[HelpFeedback] submit success status=\(statusText)")
            successMessage = "Thanks. Your feedback was sent."
            message = ""
        } catch {
            print("[HelpFeedback] submit failed error=\(error.localizedDescription)")
            submitError = feedbackErrorText(from: error)
        }
    }

    private func feedbackErrorText(from error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .statusCode(_, let data):
                if let data,
                   let text = String(data: data, encoding: .utf8),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            case .invalidRequest:
                return "Enter some feedback before sending."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

struct FeedbackSubmissionsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var submissions: [FeedbackSubmission] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                CriticDetailHeader(title: "My Feedback") {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("SUBMISSIONS")
                        .font(.critic(.sectionHeader))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .tracking(1.1)
                        .padding(.horizontal, 6)

                    if isLoading && submissions.isEmpty {
                        VStack(spacing: 14) {
                            ProgressView()
                            Text("Loading your feedback...")
                                .font(.critic(.body))
                                .foregroundColor(CriticPalette.onSurfaceMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                        .criticCard()
                    } else if let loadError {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(loadError)
                                .font(.critic(.body))
                                .foregroundColor(CriticPalette.error)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Retry") {
                                Task { await loadSubmissions() }
                            }
                            .font(.critic(.button))
                            .foregroundColor(CriticPalette.primary)
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .criticCard()
                    } else if submissions.isEmpty {
                        VStack(spacing: 12) {
                            CriticSoftIcon(
                                systemName: "bubble.left.and.bubble.right",
                                color: CriticPalette.primary,
                                size: 56,
                                iconSize: 23
                            )
                            Text("No submissions yet")
                                .font(.critic(.listTitle))
                                .foregroundColor(CriticPalette.onSurface)
                            Text("Send product feedback or bug reports from the previous screen and they will appear here.")
                                .font(.critic(.body))
                                .foregroundColor(CriticPalette.onSurfaceMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .criticCard()
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(submissions.enumerated()), id: \.offset) { _, submission in
                                FeedbackSubmissionRow(submission: submission)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .environment(\.colorScheme, .light)
        .task {
            guard submissions.isEmpty else { return }
            await loadSubmissions()
        }
        .refreshable {
            await loadSubmissions()
        }
    }

    @MainActor
    private func loadSubmissions() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            submissions = try await FeedbackService.fetchSubmissions()
            print("[FeedbackSubmissions] loaded count=\(submissions.count)")
        } catch {
            print("[FeedbackSubmissions] load failed error=\(error.localizedDescription)")
            loadError = error.localizedDescription
        }
    }
}

private struct FeedbackComposerField: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Tell us what went wrong or suggest an improvement")
                    .font(.critic(.body))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }

            TextEditor(text: $text)
                .font(.critic(.body))
                .foregroundColor(CriticPalette.onSurface)
                .modifier(ScrollBGHider())
                .frame(minHeight: 164)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CriticPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(CriticPalette.outline, lineWidth: 1)
                )
        )
    }
}

private struct FeedbackSubmissionRow: View {
    let submission: FeedbackSubmission

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(submission.statusText)
                    .font(.critic(.sectionHeader))
                    .foregroundColor(CriticPalette.onSurface)

                Spacer(minLength: 8)

                Text(formattedDate(submission.createdAt))
                    .font(.critic(.body))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
            }

            Text(submission.messageText)
                .font(.critic(.body))
                .foregroundColor(CriticPalette.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .criticCard()
    }

    private func formattedDate(_ rawValue: String?) -> String {
        guard let rawValue else { return "Submitted" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: rawValue) ?? ISO8601DateFormatter().date(from: rawValue) {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeZone = .current
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return rawValue
    }
}

// MARK: - Privacy & Visibility Screen
struct PrivacyVisibilityView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("visibility_show_name") private var showName: Bool = true
    @AppStorage("visibility_show_profile_pic") private var showProfilePic: Bool = true
    @AppStorage("visibility_show_gender") private var showGender: Bool = false

    @AppStorage("visibility_discover_by_phone") private var discoverByPhone: Bool = false
    @AppStorage("visibility_discover_by_email") private var discoverByEmail: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            CriticDetailHeader(title: "Privacy & Visibility") {
                dismiss()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            List {
                Section {
                    Toggle(isOn: $showName) {
                        Text("Name")
                            .font(.critic(.listTitle))
                            .foregroundColor(CriticPalette.onSurface)
                    }
                    Toggle(isOn: $showProfilePic) {
                        Text("Profile picture")
                            .font(.critic(.listTitle))
                            .foregroundColor(CriticPalette.onSurface)
                    }
                    Toggle(isOn: $showGender) {
                        Text("Gender")
                            .font(.critic(.listTitle))
                            .foregroundColor(CriticPalette.onSurface)
                    }
                } header: {
                    Text("Show on your profile")
                        .font(.critic(.sectionHeader))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                }

                Section {
                    Toggle(isOn: $discoverByPhone) {
                        Text("Allow discovery by phone")
                            .font(.critic(.listTitle))
                            .foregroundColor(CriticPalette.onSurface)
                    }
                    Toggle(isOn: $discoverByEmail) {
                        Text("Allow discovery by email")
                            .font(.critic(.listTitle))
                            .foregroundColor(CriticPalette.onSurface)
                    }
                } header: {
                    Text("Let others find you")
                        .font(.critic(.sectionHeader))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                } footer: {
                    Text("If enabled, people who have your contact may find you on Critic. We never show contact details.")
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                }
            }
            .modifier(ScrollBGHider())
            .listStyle(.insetGrouped)
            .tint(CriticPalette.primary)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
    }
}

// MARK: - Link Row (shared)
struct LinkRow: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button { UIApplication.shared.open(url) } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - UIKit Bridges

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    static func present(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        root.present(vc, animated: true)
    }
}

// MARK: - Real Photo Picker (PHPicker)
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { picker.dismiss(animated: true) }
            guard let provider = results.first?.itemProvider else { return }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let uiImage = object as? UIImage {
                        DispatchQueue.main.async { self.parent.image = uiImage }
                    }
                }
            }
        }
    }
}

enum AppDetector {
    static func canOpen(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}

struct ProfileModule_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { ProfileView() }.preferredColorScheme(.light)
        NavigationView { ProfileView() }.preferredColorScheme(.dark)
        NavigationView {
            ProfileView(
                otherUser: UserLocation(
                    id: "sim_1",
                    latitude: 0,
                    longitude: 0,
                    profileImageName: "person.circle.fill",
                    displayName: "Alex"
                )
            )
        }.preferredColorScheme(.light)
    }
}
