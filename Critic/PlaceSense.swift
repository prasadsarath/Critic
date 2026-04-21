//
//  PlaceSense.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/15/25.
//

import Foundation
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Coarse place kinds you care about
enum PlaceKind: String {
    case park, mall, apartment, office, campus, food, hotel, unknown
}

// MARK: - Background style for each place kind
struct BackdropStyle {
    let gradient: [Color]
    let symbol: String
    let label: String

    static func `for`(_ k: PlaceKind) -> BackdropStyle {
        switch k {
        case .park:
            return .init(gradient: [Color.blue.opacity(0.85), Color.green.opacity(0.70)],
                         symbol: "leaf.fill", label: "Park")
        case .mall:
            return .init(gradient: [Color.blue.opacity(0.85), Color.white.opacity(0.75)],
                         symbol: "bag.fill", label: "Mall")
        case .apartment:
            return .init(gradient: [Color.blue.opacity(0.85), Color.gray.opacity(0.55)],
                         symbol: "building.2.fill", label: "Apartments")
        case .office:
            return .init(gradient: [Color.blue.opacity(0.85), Color.indigo.opacity(0.65)],
                         symbol: "briefcase.fill", label: "Office")
        case .campus:
            return .init(gradient: [Color.blue.opacity(0.85), Color.teal.opacity(0.65)],
                         symbol: "graduationcap.fill", label: "Campus")
        case .food:
            return .init(gradient: [Color.blue.opacity(0.85), Color.orange.opacity(0.65)],
                         symbol: "fork.knife", label: "Food")
        case .hotel:
            return .init(gradient: [Color.blue.opacity(0.85), Color.purple.opacity(0.6)],
                         symbol: "bed.double.fill", label: "Hotel")
        case .unknown:
            return .init(gradient: [Color.blue.opacity(0.9), Color.white.opacity(0.65)],
                         symbol: "location.fill", label: "Nearby")
        }
    }
}

// MARK: - Classifier (no Google Maps)
final class PlaceClassifier {
    static let shared = PlaceClassifier()
    private let geocoder = CLGeocoder()

    func classify(coordinate: CLLocationCoordinate2D) async -> PlaceKind {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // 1) POIs within ~250m
        if #available(iOS 13.0, *) {
            let req = MKLocalPointsOfInterestRequest(center: coordinate, radius: 250)
            req.pointOfInterestFilter = MKPointOfInterestFilter(
                including: [.park, .store, .restaurant, .cafe, .school, .university, .library, .hotel]
            )
            let search = MKLocalSearch(request: req)
            if let result = try? await search.start() {
                let items = result.mapItems

                // Mall: explicit name or density of stores
                if items.contains(where: { ($0.name ?? "").localizedCaseInsensitiveContains("mall")
                                            || ($0.name ?? "").localizedCaseInsensitiveContains("shopping") }) {
                    return .mall
                }
                let stores = items.filter { $0.pointOfInterestCategory == .store }
                if stores.count >= 8 { return .mall }

                if items.contains(where: { $0.pointOfInterestCategory == .park }) { return .park }
                if items.contains(where: { $0.pointOfInterestCategory == .hotel }) { return .hotel }
                if items.contains(where: { $0.pointOfInterestCategory == .university
                                            || $0.pointOfInterestCategory == .school
                                            || $0.pointOfInterestCategory == .library }) { return .campus }
                if items.contains(where: { $0.pointOfInterestCategory == .restaurant
                                            || $0.pointOfInterestCategory == .cafe }) { return .food }
            }
        }

        // 2) Natural-language “office” / “apartment” near the user (600m box)
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
        @Sendable func find(_ q: String) async -> [MKMapItem] {
            let r = MKLocalSearch.Request()
            r.naturalLanguageQuery = q
            r.region = region
            return (try? await MKLocalSearch(request: r).start().mapItems) ?? []
        }
        async let apts = find("apartment")
        async let offs = find("office")
        let (apartments, offices) = await (apts, offs)
        if !apartments.isEmpty { return .apartment }
        if !offices.isEmpty { return .office }

        // 3) Reverse-geocode hints
        if let pm = try? await geocoder.reverseGeocodeLocation(location).first {
            if let areas = pm.areasOfInterest,
               areas.contains(where: { $0.localizedCaseInsensitiveContains("apartment")
                                        || $0.localizedCaseInsensitiveContains("residence")
                                        || $0.localizedCaseInsensitiveContains("condo") }) {
                return .apartment
            }
        }

        return .unknown
    }
}

// MARK: - ViewModel to share with UI
@MainActor
final class PlaceSenseViewModel: ObservableObject {
    @Published var kind: PlaceKind = .unknown
    var backdrop: BackdropStyle { BackdropStyle.for(kind) }

    func update(with location: CLLocation) {
        Task {
            let k = await PlaceClassifier.shared.classify(coordinate: location.coordinate)
            self.kind = k
        }
    }
}

// MARK: - Background view
struct BackdropView: View {
    let style: BackdropStyle
    @State private var pulse = false

    var body: some View {
        LinearGradient(colors: style.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                ZStack {
                    // big translucent symbol
                    Image(systemName: style.symbol)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .opacity(0.08)
                        .scaleEffect(pulse ? 1.03 : 0.97)
                        .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: pulse)

                    // subtle label
                    VStack {
                        Text(style.label)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.65))
                            .padding(.top, 8)
                        Spacer()
                    }
                }
            )
            .onAppear { pulse = true }
    }
}
