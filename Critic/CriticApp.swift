import SwiftUI
import UIKit
import SafariServices

@main
struct CriticApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false   // single source of truth

    // Drives whether StartupAuthView should auto-present Hosted UI
    private enum Phase { case checking, needsLogin, loggedIn }
    @State private var phase: Phase

    init() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let hasSavedSession = OIDCAuthManager.shared.hasAuthState
        let isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")

        if !hasCompletedOnboarding {
            _phase = State(initialValue: .checking)
        } else if hasSavedSession || isLoggedIn {
            _phase = State(initialValue: .checking)
        } else {
            _phase = State(initialValue: .needsLogin)
        }
    }

    private func bootstrapAuthIfNeeded() {
        guard hasCompletedOnboarding else {
            phase = .checking
            return
        }

        // Always load any persisted auth state once the user is past onboarding.
        OIDCAuthManager.shared.loadAuthState()

        guard OIDCAuthManager.shared.hasAuthState else {
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            phase = .needsLogin
            return
        }

        // We have a saved session; keep the user in-app and refresh quietly.
        isLoggedIn = true
        phase = .checking
        OIDCAuthManager.shared.refreshIfNeeded { ok in
            DispatchQueue.main.async {
                if ok {
                    self.isLoggedIn = true
                    self.phase = .loggedIn
                } else {
                    // If refresh fails, keep the session unless it's truly gone.
                    if OIDCAuthManager.shared.hasAuthState {
                        self.isLoggedIn = true
                        self.phase = .loggedIn
                    } else {
                        self.isLoggedIn = false
                        self.phase = .needsLogin
                    }
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !hasCompletedOnboarding {
                    OnboardingView()
                } else {
                    switch phase {
                    case .loggedIn:
                        HomeView()

                    case .needsLogin:
                        // Require explicit user action to present Hosted UI
                        StartupAuthView(autoPresent: false)

                    case .checking:
                        StartupLoadingView()
                    }
                }
            }
            // Keep UI in sync with auth notifications
            .onReceive(NotificationCenter.default.publisher(for: .didLogin)) { _ in
                isLoggedIn = true
                if hasCompletedOnboarding {
                    phase = .loggedIn
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didLogout)) { _ in
                isLoggedIn = false
                guard hasCompletedOnboarding else { return }
                phase = .needsLogin
            }
            .onReceive(NotificationCenter.default.publisher(for: .verificationNeeded)) { _ in
                isLoggedIn = false
                guard hasCompletedOnboarding else { return }
                phase = .needsLogin
            }
            .onReceive(NotificationCenter.default.publisher(for: .loginFailed)) { _ in
                guard hasCompletedOnboarding else { return }
                if !isLoggedIn { phase = .needsLogin }
            }
            .onAppear {
                bootstrapAuthIfNeeded()
            }
            .onChange(of: hasCompletedOnboarding) { completed in
                if completed {
                    bootstrapAuthIfNeeded()
                } else {
                    phase = .checking
                }
            }
        }
    }
}

private struct StartupLoadingView: View {
    var body: some View {
        ZStack {
            CriticPalette.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("StartupHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .accessibilityHidden(true)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(CriticPalette.primary)

                Text("Restoring your session...")
                    .font(.critic(.body))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
            }
        }
    }
}

/// Startup “welcome to Critic” screen that can auto-present the Hosted UI.
/// No business-logic changes—just prevents unwanted prompts while we're silently refreshing.
import SwiftUI

/// Startup “welcome to Critic” screen that can auto-present the Hosted UI.
/// No business-logic changes—just prevents unwanted prompts while we're silently refreshing.
struct StartupAuthView: View {
    var autoPresent: Bool = true
    @State private var hasAutoPresented = false
    @State private var safariItem: SafariItem? = nil
    @Environment(\.scenePhase) private var scenePhase

    private func isAppReadyForAuth() -> Bool {
        UIApplication.shared.applicationState == .active && UIApplication.shared.topViewController() != nil
    }

    var body: some View {
        ZStack {
            CriticPalette.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    Text("Welcome to Critic")
                        .font(.critic(.display))
                        .foregroundColor(CriticPalette.onSurface)
                        .multilineTextAlignment(.center)

                    Text("Share honest feedback, stay safe, and connect with people nearby.")
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 24)

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        CriticPalette.primary.opacity(0.12),
                                        CriticPalette.accent.opacity(0.07),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 8,
                                    endRadius: 88
                                )
                            )
                            .frame(width: 168, height: 168)

                        _StartupHeroBadge(systemName: "checkmark.shield", color: CriticPalette.success)
                            .offset(x: -50, y: -44)
                        _StartupHeroBadge(systemName: "location", color: CriticPalette.info)
                            .offset(x: 52, y: -38)
                        _StartupHeroBadge(systemName: "person.2", color: CriticPalette.accent)
                            .offset(x: 28, y: 54)

                        Image("StartupHero")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                            .accessibilityLabel("Critic logo")
                    }

                    VStack(spacing: 10) {
                        _StartupFeatureLine(
                            systemName: "eye.slash",
                            title: "Private feedback",
                            subtitle: "Your name stays private, so people can be direct."
                        )
                        _StartupFeatureLine(
                            systemName: "location.magnifyingglass",
                            title: "Nearby context",
                            subtitle: "See nearby people and reviews that are relevant to you."
                        )
                        _StartupFeatureLine(
                            systemName: "checklist.checked",
                            title: "Moderated posting",
                            subtitle: "Posts are reviewed to keep conversations respectful."
                        )
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: 320)

                Spacer(minLength: 24)

                Button {
                    presentHostedUI()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Sign in")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CriticFilledButtonStyle())

                Text("By tapping sign in you Agree our terms & conditions")
                    .font(.critic(.caption))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 12)

                HStack(spacing: 10) {
                    _StartupLinkChip(title: "Terms & Conditions") {
                        safariItem = SafariItem(url: AppExternalLinks.terms)
                    }
                    _StartupLinkChip(title: "Privacy Policy") {
                        safariItem = SafariItem(url: AppExternalLinks.privacy)
                    }
                    _StartupLinkChip(title: "FAQs") {
                        safariItem = SafariItem(url: AppExternalLinks.faq)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)

            .sheet(item: $safariItem) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }

            // Auto-present logic
            Color.clear
                .onAppear {
                    // Reset each time this screen becomes visible so logout → login re-triggers Hosted UI
                    hasAutoPresented = false
                    triggerAutoPresentIfNeeded(reason: "onAppear")
                }
                .onChange(of: autoPresent) { _ in
                    // If the parent flips from false → true (e.g., token refresh failed), allow re-prompt
                    hasAutoPresented = false
                    triggerAutoPresentIfNeeded(reason: "autoPresent toggled")
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        hasAutoPresented = false
                        triggerAutoPresentIfNeeded(reason: "scene active")
                    }
                }
        }
    }

    private func triggerAutoPresentIfNeeded(reason: String, attempt: Int = 0) {
        guard autoPresent, !hasAutoPresented else {
            print("[Auth] Auto-present skipped (autoPresent=\(autoPresent) hasAutoPresented=\(hasAutoPresented)) reason=\(reason)")
            return
        }
        guard isAppReadyForAuth(), let topVC = UIApplication.shared.topViewController() else {
            let nextAttempt = attempt + 1
            if nextAttempt <= 5 {
                let delay = Double(nextAttempt) * 0.4
                print("[Auth] Auto-present deferred (\(reason)) attempt=\(nextAttempt) delay=\(delay)s (app not active or no presenter)")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    triggerAutoPresentIfNeeded(reason: reason, attempt: nextAttempt)
                }
            } else {
                print("[Auth] Auto-present abandoned after retries. reason=\(reason)")
            }
            return
        }
        hasAutoPresented = true
        // Tiny delay so rootVC exists
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            print("[Auth] Auto-present Hosted UI. reason=\(reason)")
            presentHostedUI(using: topVC)
        }
    }

    private func presentHostedUI(using presenter: UIViewController? = nil) {
        guard !OIDCAuthManager.shared.isSigningIn else { return }
        let vc = presenter ?? UIApplication.shared.topViewController()
        guard let presenter = vc else {
            print("[Auth] presentHostedUI skipped: no presenter")
            return
        }
        OIDCAuthManager.shared.signIn(presentingViewController: presenter)
    }
}

private struct _StartupHeroBadge: View {
    let systemName: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CriticPalette.surface.opacity(0.96))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            )
    }
}

private struct _StartupFeatureLine: View {
    let systemName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CriticSoftIcon(systemName: systemName, color: CriticPalette.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.critic(.cardTitle))
                    .foregroundColor(CriticPalette.onSurface)
                Text(subtitle)
                    .font(.critic(.caption))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct _StartupLinkChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.critic(.caption))
                .foregroundColor(CriticPalette.onSurfaceMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(CriticPalette.surface)
                        .overlay(Capsule(style: .continuous).stroke(CriticPalette.outline, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct SafariItem: Identifiable {
    let id = UUID()
    let url: URL
}
