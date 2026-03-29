import Combine
import CoreLocation
import Foundation

@MainActor
final class NavigationManager: ObservableObject {
    static let shared = NavigationManager()

    @Published var showInbox = false
    @Published var showProfile = false
    @Published var showWritePost = false
    @Published var selectedUser: UserLocation?
    @Published var selectedDistance: Double?
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private enum StorageKey {
        static let latitude = "lastKnownLatitude"
        static let longitude = "lastKnownLongitude"
    }

    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var currentAddress = "Enable location to see people nearby"
    @Published var authorizationStatus: CLAuthorizationStatus

    private var lastGeocodeTime: Date = .distantPast
    private let geocodeCooldown: TimeInterval = 10

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 25
        beginMonitoringIfAuthorized()
    }

    var effectiveCoordinate: CLLocationCoordinate2D? {
        if let current = currentLocation?.coordinate {
            return current
        }

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            return nil
        }

        return lastKnownCoordinate
    }

    var lastKnownCoordinate: CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: StorageKey.latitude) != nil,
              defaults.object(forKey: StorageKey.longitude) != nil else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: defaults.double(forKey: StorageKey.latitude),
            longitude: defaults.double(forKey: StorageKey.longitude)
        )
    }

    func beginMonitoringIfAuthorized() {
        authorizationStatus = currentAuthorizationStatus()
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                currentAddress = "Enable location in Settings to see people nearby"
            }
            return
        }

        if currentLocation == nil {
            currentAddress = "Locating..."
            locationManager.requestLocation()
        }
        locationManager.startUpdatingLocation()
    }

    func requestAccessIfNeeded() {
        authorizationStatus = currentAuthorizationStatus()

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginMonitoringIfAuthorized()
        case .notDetermined:
            currentAddress = "Allow location to see people nearby"
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            currentAddress = "Enable location in Settings to see people nearby"
        @unknown default:
            currentAddress = "Enable location to see people nearby"
        }
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginMonitoringIfAuthorized()
        case .denied, .restricted:
            currentLocation = nil
            currentAddress = "Enable location in Settings to see people nearby"
            stopUpdating()
        case .notDetermined:
            currentAddress = "Enable location to see people nearby"
        @unknown default:
            currentAddress = "Enable location to see people nearby"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = location
            UserDefaults.standard.set(location.coordinate.latitude, forKey: StorageKey.latitude)
            UserDefaults.standard.set(location.coordinate.longitude, forKey: StorageKey.longitude)
            self.tryReverseGeocode(location: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if currentLocation == nil {
            currentAddress = "Unable to determine your location"
        }
    }

    private func currentAuthorizationStatus() -> CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    private func tryReverseGeocode(location: CLLocation) {
        let now = Date()
        guard now.timeIntervalSince(lastGeocodeTime) > geocodeCooldown else { return }
        lastGeocodeTime = now
        reverseGeocode(location: location)
    }

    private func reverseGeocode(location: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            guard let placemark = placemarks?.first, error == nil else {
                if self.currentLocation != nil {
                    self.currentAddress = "Unable to fetch address"
                }
                return
            }
            self.currentAddress = [
                placemark.name,
                placemark.locality,
                placemark.administrativeArea
            ].compactMap { $0 }.joined(separator: ", ")
        }
    }
}

final class InboxCountViewModel: ObservableObject {
    @Published var count = 0

    private let listURL = AppEndpoints.Gateway.posts
    private var ticker: AnyCancellable?

    private struct FeedResponse: Codable {
        let myPosts: [PostItem]
        let receivedPosts: [PostItem]
    }

    private struct PostItem: Codable {
        let postId: String
        let poststatus: String?
    }

    func start(userId: String, every seconds: TimeInterval = 15) {
        stop()
        Task { await fetch(userId: userId) }
        ticker = Timer.publish(every: seconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.fetch(userId: userId) }
            }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    private func fetch(userId: String) async {
        do {
            guard OIDCAuthManager.shared.hasAuthState else {
                print("[InboxVM] skipped fetch: missing access token")
                return
            }
            let request = APIRequestDescriptor(
                url: listURL,
                queryItems: [URLQueryItem(name: "userId", value: userId)],
                authorization: .currentUser
            )
            let (data, _) = try await APIRequestExecutor.shared.perform(request)
            let decoded = try JSONDecoder().decode(FeedResponse.self, from: data)
            await MainActor.run {
                self.count = decoded.receivedPosts.count
            }
        } catch {
            print("[InboxVM][ERROR] \(error.localizedDescription)")
        }
    }
}
