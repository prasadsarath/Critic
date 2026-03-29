//
//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//

import SwiftUI
import UIKit
import MessageUI
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
        case deleteRequestComposer

        var id: Int { rawValue }
    }

    private enum ActiveAlert: Int, Identifiable {
        case logout
        case deleteRequestFallback

        var id: Int { rawValue }
    }

    @Binding var profileImage: Image
    @Binding var hasCustomProfileImage: Bool
    @Binding var name: String
    @Binding var email: String
    @Binding var bio: String

    @AppStorage("userName") private var userName: String = "Guest"
    @AppStorage("userEmail") private var userEmail: String = "guest@example.com"

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
        let value = UserDefaults.standard.string(forKey: "userProfileUrl")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                VStack(spacing: 18) {
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

                    Text(name)
                        .font(.critic(.display))
                        .foregroundColor(CriticPalette.onSurface)
                        .multilineTextAlignment(.center)

                    Text(email)
                        .font(.critic(.bodyStrong))
                        .foregroundColor(CriticPalette.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CriticPalette.surface)
                                .overlay(Capsule(style: .continuous).stroke(CriticPalette.outline, lineWidth: 1))
                        )
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
                            onSave: { newName, newEmail, newBio, newImage in
                                self.name = newName
                                self.email = newEmail
                                self.userName = newName
                                self.userEmail = newEmail
                                self.bio = newBio
                                if let newImage {
                                    self.profileImage = newImage
                                    self.hasCustomProfileImage = true
                                }
                            }
                        )
                        .navigationBarBackButtonHidden(false),
                    isActive: $pushEdit
                ) { EmptyView() }

                NavigationLink(
                    destination: SettingsView(
                        onLogout: { activeAlert = .logout },
                        onRequestAccountDeletion: { presentAccountDeletionRequest() }
                    )
                        .navigationBarBackButtonHidden(false),
                    isActive: $pushSettings
                ) { EmptyView() }
            }
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .criticNavigationBarBackground(CriticPalette.background)
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
            case .deleteRequestComposer:
                MailComposeView(
                    recipients: [AppExternalLinks.contactEmail],
                    subject: "Critic Account Deletion Request",
                    body: deletionRequestBody
                )
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
            case .deleteRequestFallback:
                return Alert(
                    title: Text("Mail isn’t available"),
                    message: Text("Use \(AppExternalLinks.contactEmail) to request account deletion."),
                    dismissButton: .cancel(Text("OK"))
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

    private var deletionRequestBody: String {
        let resolvedEmail = meVM.identity?.email ?? email
        let resolvedUserId = meVM.identity?.sub ?? UserDefaults.standard.string(forKey: "userId") ?? "Unknown"
        return """
        Hello Critic support,

        I want to request deletion of my Critic account.

        Account email: \(resolvedEmail)
        Account user ID: \(resolvedUserId)

        Please confirm when the deletion request has been processed.
        """
    }

    private func presentAccountDeletionRequest() {
        if MFMailComposeViewController.canSendMail() {
            activeSheet = .deleteRequestComposer
            return
        }

        guard let encodedSubject = "Critic Account Deletion Request".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = deletionRequestBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let fallbackURL = URL(string: "mailto:\(AppExternalLinks.contactEmail)?subject=\(encodedSubject)&body=\(encodedBody)") else {
            activeAlert = .deleteRequestFallback
            return
        }

        if UIApplication.shared.canOpenURL(fallbackURL) {
            UIApplication.shared.open(fallbackURL)
        } else {
            activeAlert = .deleteRequestFallback
        }
    }

    private func performLogout() {
        OIDCAuthManager.shared.signOut()
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(true, forKey: "justLoggedOut")
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        profileImage = Image(systemName: "person.circle.fill")
        hasCustomProfileImage = false
        NavigationManager.shared.showInbox = false
        NavigationManager.shared.showWritePost = false
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
                .fill(
                    LinearGradient(
                        colors: [
                            CriticPalette.surface,
                            CriticPalette.primarySoft.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(CriticPalette.outline, lineWidth: 1)

            Image("StartupHero")
                .resizable()
                .scaledToFit()
                .padding(size * 0.2)
                .opacity(0.24)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: 0x151A2D, alpha: 0.03), radius: 8, x: 0, y: 3)
        .accessibilityLabel("Default profile logo")
    }
}

// MARK: - External Profile Content (common UI used everywhere)
private struct ExternalProfileContent: View {
    let user: UserLocation

    private var resolvedDisplayName: String {
        DisplayNameResolver.resolve(displayName: user.displayName, userId: user.id)
    }

    private var navigationTitleText: String {
        let trimmed = resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "User" ? "Profile" : trimmed
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                VStack(spacing: 16) {
                    AvatarView(
                        urlString: user.profileUrl,
                        seed: user.displayName ?? user.id,
                        fallbackSystemName: user.profileImageName,
                        size: 108,
                        backgroundColor: CriticPalette.surface,
                        tintColor: CriticPalette.primary
                    )

                    Text(resolvedDisplayName)
                        .font(.critic(.display))
                        .foregroundColor(CriticPalette.onSurface)
                        .multilineTextAlignment(.center)

                    Text("Exploring places nearby…")
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .criticCard()

                VStack(spacing: 0) {
                    ProfileInfoRow(title: "Posts", value: "—")
                    Divider().padding(.leading, 16)
                    ProfileInfoRow(title: "About", value: "Exploring places nearby…")
                }
                .criticCard()

                Button {
                    NavigationManager.shared.selectedUser = user
                    NavigationManager.shared.selectedDistance = nil
                    NavigationManager.shared.showWritePost = true
                } label: {
                    Text("Write")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CriticFilledButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .criticNavigationBarBackground(CriticPalette.background)
    }
}

// MARK: - Profile Menu Row
struct ProfileMenuRow: View {
    var icon: String
    var text: String
    var textColor: Color = .primary
    var iconColor: Color = .accentColor
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
                    .font(.critic(.body))
                    .foregroundColor(textColor)
                Spacer()
                if text != "Logout" {
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

// MARK: - Edit Profile View (iOS 15 safe)
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State var name: String
    @State var email: String
    @State var bio: String
    @State var image: Image
    var onSave: (_ name: String, _ email: String, _ bio: String, _ newImage: Image?) -> Void

    @State private var showPhotoSheet = false
    @State private var pickedUIImage: UIImage?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(.systemGray5), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your public Avatar")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Change Photo") {
                            showPhotoSheet = true
                        }
                    }
                }
            }

            Section(header: Text("How others see you")) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.body)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("When you post, you will appear as.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField("Full Name", text: $name)
                            .textContentType(.name)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "envelope")
                        .foregroundColor(.accentColor)
                        .font(.body)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("e-Mail")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(email)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Bio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $bio)
                        .frame(minHeight: 80, maxHeight: 140)
                }
            }

            Section {
                Button("Save") {
                    let newImage: Image? = pickedUIImage.map { Image(uiImage: $0) }
                    onSave(name, email, bio, newImage)
                    dismiss()
                }
                .font(.headline)
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPhotoSheet) {
            PhotoPicker(image: $pickedUIImage)
                .onChange(of: pickedUIImage) { newValue in
                    if let ui = newValue { image = Image(uiImage: ui) }
                }
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
            VStack(spacing: 16) {
                Text("Invite a friend")
                    .font(.system(.title3, design: .rounded)).bold()
                    .padding(.top, 8)

                Text("Share your invite link using your favorite app.")
                    .font(.caption)
                    .foregroundColor(.secondary)

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
                .padding(.top, 6)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
    }
}

// MARK: - Settings View (iOS 15 safe)
struct SettingsView: View {
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("dark_mode_enabled") private var darkModeEnabled = false

    var onLogout: () -> Void
    var onRequestAccountDeletion: () -> Void

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Notification", systemImage: "bell")
                    Spacer()
                    Toggle("", isOn: $notificationsEnabled).labelsHidden()
                }

                Button { darkModeEnabled.toggle() } label: {
                    Label("Dark Mode", systemImage: "sun.max").foregroundColor(.primary)
                }

                Button {
                    AppReviewRequester.requestReview()
                } label: {
                    Label("Rate App", systemImage: "star")
                }

                Button { ShareSheet.present(items: ["Check out Critic!", AppExternalLinks.website]) } label: {
                    Label("Share App", systemImage: "square.and.arrow.up")
                }
            }

            Section {
                NavigationLink {
                    PrivacyVisibilityView()
                } label: {
                    Label("Privacy", systemImage: "lock")
                }

                LinkRow(
                    title: "Terms and Conditions",
                    systemImage: "doc.text",
                    url: AppExternalLinks.terms
                )
                LinkRow(title: "Cookies Policy", systemImage: "doc.on.doc", url: AppExternalLinks.cookies)
            }

            Section {
                LinkRow(title: "Contact", systemImage: "envelope", url: AppExternalLinks.contactMailtoURL)
                LinkRow(title: "Feedback", systemImage: "bubble.right", url: AppExternalLinks.feedback)
            }

            Section {
                Button(role: .destructive) { onLogout() } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.red)
                }

                Button(role: .destructive) { onRequestAccountDeletion() } label: {
                    Label("Request Account Deletion", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.colorScheme, darkModeEnabled ? .dark : .light)
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
        List {
            Section(header: Text("Show on your profile")) {
                Toggle("Name", isOn: $showName)
                Toggle("Profile picture", isOn: $showProfilePic)
                Toggle("Gender", isOn: $showGender)
            }

            Section {
                Toggle("Allow discovery by phone", isOn: $discoverByPhone)
                Toggle("Allow discovery by email", isOn: $discoverByEmail)
            } header: {
                Text("Let others find you")
            } footer: {
                Text("If enabled, people who have your contact may find you on Critic. We never show contact details.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy & Visibility")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    dismiss()
                }
            }
        }
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

struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismiss()
        }
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
