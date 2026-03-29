//
//  WelcomeScreens.swift
//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//
import SwiftUI
import WebKit

struct OnboardingData {
    let image: String
    let title: String
    let subtitle: String
    let highlights: [String]
    let primaryColor: Color
    let secondaryColor: Color
    let ambientIcons: [String]
}

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var showLogoutSuccess: Bool = false
    @State private var currentPage: Int = 0
    @State private var showWebView: Bool = false
    @State private var webViewURL: URL? = nil
    @GestureState private var dragOffset: CGFloat = 0

    let pages = [
        OnboardingData(
            image: "bubble.left.and.bubble.right",
            title: "Get honest feedback\nthat helps you grow",
            subtitle: "Share honest thoughts in a calm, respectful space.",
            highlights: [
                "Your identity stays private while people stay honest.",
                "Prompts keep feedback clear and useful.",
                "Harmful content is filtered before posting."
            ],
            primaryColor: Color(hex: 0x0EA5A4),
            secondaryColor: Color(hex: 0x22C55E),
            ambientIcons: ["bubble.left", "eye", "checkmark.shield"]
        ),
        OnboardingData(
            image: "safari",
            title: "See what people\naround you are saying",
            subtitle: "Nearby feedback helps you understand local experiences better.",
            highlights: [
                "Spot patterns from people nearby.",
                "See if feedback is one-off or repeated.",
                "Write when your feedback is relevant."
            ],
            primaryColor: Color(hex: 0x0EA5E9),
            secondaryColor: CriticPalette.warning,
            ambientIcons: ["location", "point.topleft.down.curvedto.point.bottomright.up", "person.2"]
        ),
        OnboardingData(
            image: "bell.badge",
            title: "Post with confidence\nand control",
            subtitle: "Write, review, and share feedback in a simple, safe flow.",
            highlights: [
                "Review your post before sharing.",
                "Post now or schedule for later.",
                "Find friends on Critic and invite more people."
            ],
            primaryColor: Color(hex: 0xF97316),
            secondaryColor: Color(hex: 0xEF4444),
            ambientIcons: ["clock", "lock.shield", "person.2.badge.plus"]
        )
    ]

    var body: some View {
        let page = pages[currentPage]

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == currentPage ? page.primaryColor : CriticPalette.outline)
                        .frame(height: 4)
                }

                Button("Skip") {
                    hasCompletedOnboarding = true
                }
                .font(.critic(.button))
                .foregroundColor(CriticPalette.primary)
                .padding(.leading, 12)
            }
            .frame(height: 28)
            .padding(.horizontal, 24)
            .padding(.top, 18)

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    onboardingSlide(for: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                if currentPage > 0 {
                    Button {
                        withAnimation(.easeOut(duration: 0.22)) {
                            currentPage -= 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left")
                            Text("Back")
                        }
                        .frame(minWidth: 84)
                    }
                    .buttonStyle(CriticOutlinedButtonStyle())
                } else {
                    Spacer().frame(width: 84)
                }

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.22)) {
                        if currentPage < pages.count - 1 {
                            currentPage += 1
                        } else {
                            hasCompletedOnboarding = true
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: currentPage == pages.count - 1 ? "checkmark" : "arrow.right")
                        Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                    }
                    .frame(minWidth: 150)
                }
                .buttonStyle(CriticFilledButtonStyle(backgroundColor: page.primaryColor))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(CriticPalette.background.ignoresSafeArea())
        .onAppear {
            // Reset any lingering nav flags
            DispatchQueue.main.async {
                NavigationManager.shared.showProfile = false
                NavigationManager.shared.showInbox = false
                NavigationManager.shared.showWritePost = false
            }
        }
        .alert("Logged out successfully", isPresented: $showLogoutSuccess) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showWebView) {
            if let url = webViewURL {
                WebView(url: url)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text("Unable to load page.")
            }
        }
    }

    @ViewBuilder
    private func onboardingSlide(for page: OnboardingData) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    page.primaryColor.opacity(0.18),
                                    page.secondaryColor.opacity(0.10),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 126
                            )
                        )
                        .frame(width: 252, height: 252)

                    ForEach(Array(page.ambientIcons.enumerated()), id: \.offset) { index, icon in
                        let positions: [CGSize] = [
                            CGSize(width: -112, height: -74),
                            CGSize(width: 104, height: -70),
                            CGSize(width: -82, height: 44),
                            CGSize(width: 92, height: 40),
                            CGSize(width: -28, height: 110),
                            CGSize(width: 62, height: 100)
                        ]
                        let colors: [Color] = [
                            page.primaryColor,
                            page.secondaryColor,
                            CriticPalette.info,
                            CriticPalette.warning,
                            CriticPalette.accent,
                            CriticPalette.success
                        ]

                        if index < positions.count {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(CriticPalette.surface.opacity(0.96))
                                .frame(width: 46, height: 46)
                                .overlay(
                                    Image(systemName: icon)
                                        .font(.system(size: 21, weight: .semibold))
                                        .foregroundColor(colors[index])
                                )
                                .offset(positions[index])
                        }
                    }

                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [page.primaryColor, page.secondaryColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 116, height: 116)
                        .overlay(
                            Image(systemName: page.image)
                                .font(.system(size: 46, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)

                VStack(alignment: .leading, spacing: 12) {
                    Text(page.title)
                        .font(.critic(.display))
                        .foregroundColor(CriticPalette.onSurface)

                    Text(page.subtitle)
                        .font(.critic(.body))
                        .foregroundColor(CriticPalette.onSurfaceMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    ForEach(Array(page.highlights.enumerated()), id: \.offset) { index, highlight in
                        HStack(alignment: .top, spacing: 10) {
                            CriticSoftIcon(
                                systemName: index == 0 ? "sparkles" : index == 1 ? "list.bullet.clipboard" : "checkmark.shield",
                                color: index == 0 ? page.primaryColor : index == 1 ? page.secondaryColor : CriticPalette.success
                            )
                            Text(highlight)
                                .font(.critic(.body))
                                .foregroundColor(CriticPalette.onSurface)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .criticCard()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                HStack(spacing: 10) {
                    Button("Privacy") {
                        webViewURL = AppExternalLinks.privacy
                        showWebView = true
                    }
                    .buttonStyle(.plain)
                    .font(.critic(.caption))
                    .foregroundColor(CriticPalette.onSurfaceMuted)

                    Button("Terms") {
                        webViewURL = AppExternalLinks.terms
                        showWebView = true
                    }
                    .buttonStyle(.plain)
                    .font(.critic(.caption))
                    .foregroundColor(CriticPalette.onSurfaceMuted)

                    Button("FAQs") {
                        webViewURL = AppExternalLinks.faq
                        showWebView = true
                    }
                    .buttonStyle(.plain)
                    .font(.critic(.caption))
                    .foregroundColor(CriticPalette.onSurfaceMuted)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
