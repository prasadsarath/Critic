import SwiftUI
import CoreLocation

struct PublicProfileView: View {
    let user: UserLocation

    // Use the distance already computed by HomeView (if available)
    private var selectedDistance: Double? {
        NavigationManager.shared.selectedDistance
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 24)

            Image(systemName: user.profileImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundColor(.blue)
                .background(Circle().fill(Color(.secondarySystemBackground)))
                .clipShape(Circle())

            Text(user.displayName ?? user.id)
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            if let d = selectedDistance {
                Text("\(formatMetersLocal(d)) away")
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

