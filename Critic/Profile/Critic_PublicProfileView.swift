import SwiftUI
import CoreLocation

struct PublicProfileView: View {
    let user: UserLocation

    // Use the distance already computed by HomeView (if available)
    private var selectedDistance: Double? {
        liveDistanceMeters(to: hydratedUser, fallback: NavigationManager.shared.selectedDistance)
    }

    private var hydratedUser: UserLocation {
        KnownUserDirectory.hydrated(user)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 24)

            AvatarView(
                urlString: hydratedUser.profileUrl,
                seed: resolvedUserSeed(hydratedUser),
                fallbackSystemName: hydratedUser.profileImageName,
                size: 96,
                backgroundColor: Color(.secondarySystemBackground),
                tintColor: CriticPalette.primary
            )

            Text(resolvedUserDisplayName(hydratedUser))
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            if let d = selectedDistance {
                Text("\(formatMetersLocal(d)) away")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let email = DisplayNameResolver.normalizedEmail(hydratedUser.email) {
                Text(email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Add more public fields here as you introduce them (bio, mutuals, etc.)

            Spacer()
        }
        .padding()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Local helpers (keep this file self-contained)
private func formatMetersLocal(_ meters: Double) -> String {
    if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
    return String(format: "%.0f m", meters)
}
