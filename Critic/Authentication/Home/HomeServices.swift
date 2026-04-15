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
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var currentAddress = "Enable location to see people nearby"
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var accuracyAuthorization: CLAccuracyAuthorization

    private var lastGeocodeTime: Date = .distantPast
    private let geocodeCooldown: TimeInterval = 10
    private var recentGoodLocations: [CLLocation] = []
    private var lastTemporaryFullAccuracyRequestAt: Date = .distantPast
    private let temporaryFullAccuracyRequestCooldown: TimeInterval = 60

    /// Creates and configures the nearby location manager.
    ///
    /// The initializer captures the current authorization state, applies high-accuracy Core Location
    /// settings for nearby detection, and begins monitoring immediately when permission is already granted.
    override init() {
        authorizationStatus = locationManager.authorizationStatus
        accuracyAuthorization = locationManager.accuracyAuthorization
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
        beginMonitoringIfAuthorized()
    }

    /// Returns the freshest nearby-ready location available to the app.
    ///
    /// Live GPS is preferred when it passes the nearby policy checks. If no current fix is usable,
    /// the manager falls back to the last persisted device location while authorization remains valid.
    ///
    /// - Returns: A validated `CLLocation` for nearby logic, or `nil` when no safe fix exists.
    var effectiveLocation: CLLocation? {
        let now = Date()
        if let currentLocation,
           isUsableNearbyLocation(currentLocation, maxAge: NearbyLocationPolicy.maxLiveLocationAge, now: now) {
            return currentLocation
        }

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            return nil
        }

        if let storedLocation = currentStoredDeviceLocation(now: now) {
            return storedLocation
        }

        return lastPersistedNearbyLocation()
    }

    /// Exposes the best available coordinate for nearby socket updates.
    ///
    /// This computed property unwraps `effectiveLocation` so callers that only need latitude and
    /// longitude do not have to duplicate the validation logic.
    ///
    /// - Returns: A validated `CLLocationCoordinate2D`, or `nil` when no usable location exists.
    var effectiveCoordinate: CLLocationCoordinate2D? {
        effectiveLocation?.coordinate
    }

    /// Returns the last persisted coordinate that still passes nearby validation.
    ///
    /// This is primarily used as a lightweight convenience for code that only needs a cached
    /// coordinate and does not require the full `CLLocation` metadata.
    ///
    /// - Returns: The last valid persisted coordinate, or `nil` when cached data is missing or stale.
    var lastKnownCoordinate: CLLocationCoordinate2D? {
        currentStoredDeviceLocation()?.coordinate
    }

    /// Starts nearby monitoring when location permission is already available.
    ///
    /// The manager refreshes authorization state, requests temporary precise location when needed,
    /// triggers a one-shot location request if no usable fix exists yet, and then starts continuous updates.
    func beginMonitoringIfAuthorized() {
        authorizationStatus = currentAuthorizationStatus()
        accuracyAuthorization = locationManager.accuracyAuthorization
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                currentAddress = "Enable location in Settings to see people nearby"
            }
            return
        }

        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        requestTemporaryFullAccuracyIfNeeded()

        if effectiveLocation == nil {
            currentAddress = pendingLocationMessage()
            locationManager.requestLocation()
        }
        locationManager.startUpdatingLocation()
    }

    /// Requests location access when the nearby feature needs it.
    ///
    /// Authorized users move directly into active monitoring, undecided users are prompted for
    /// `when in use` permission, and denied users receive a Settings-focused status message.
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

    /// Stops continuous location updates for the nearby feature.
    ///
    /// This also clears the in-memory smoothing buffer so the next tracking session starts with
    /// fresh GPS samples instead of reusing older nearby fixes.
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
        recentGoodLocations.removeAll(keepingCapacity: true)
    }

    /// Responds to authorization or precise-location accuracy changes from Core Location.
    ///
    /// The method keeps the published authorization state in sync with the system and starts or
    /// stops nearby tracking based on the latest permission outcome.
    ///
    /// - Parameter manager: The `CLLocationManager` reporting the authorization change.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        print("[GPS] Authorization changed status=\(authorizationStatus.rawValue) accuracy=\(accuracyAuthorization == .fullAccuracy ? "full" : "reduced")")

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginMonitoringIfAuthorized()
        case .denied, .restricted:
            currentLocation = nil
            recentGoodLocations.removeAll(keepingCapacity: true)
            currentAddress = "Enable location in Settings to see people nearby"
            stopUpdating()
        case .notDetermined:
            currentAddress = "Enable location to see people nearby"
        @unknown default:
            currentAddress = "Enable location to see people nearby"
        }
    }

    /// Processes raw GPS fixes delivered by Core Location.
    ///
    /// Every incoming location is logged, filtered by the nearby accuracy policy, smoothed through
    /// a short median window, and then persisted for both UI and socket usage.
    ///
    /// - Parameters:
    ///   - manager: The `CLLocationManager` delivering the update.
    ///   - locations: The batch of raw `CLLocation` fixes from Core Location.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let now = Date()
        print("[GPS] Raw fixes: \(locationDebugDescriptions(for: locations, now: now))")
        let goodLocations = locations.filter {
            isUsableNearbyLocation($0, maxAge: NearbyLocationPolicy.maxIncomingLocationAge, now: now)
        }

        guard !goodLocations.isEmpty else {
            print("[GPS] Rejected all fixes after nearby filtering")
            DispatchQueue.main.async {
                if self.currentLocation == nil {
                    self.currentAddress = self.pendingLocationMessage()
                }
            }
            return
        }

        print("[GPS] Accepted fixes: \(locationDebugDescriptions(for: goodLocations, now: now))")
        recentGoodLocations.append(contentsOf: goodLocations)
        recentGoodLocations = Array(recentGoodLocations.suffix(NearbyLocationPolicy.smoothingWindowSize))
        guard let location = medianLocation(from: recentGoodLocations) else { return }
        print("[GPS] Smoothed fix selected: \(locationDebugDescription(for: location, now: now))")

        DispatchQueue.main.async {
            self.currentLocation = location
            self.persist(location: location)
            self.tryReverseGeocode(location: location)
        }
    }

    /// Handles Core Location failures while nearby tracking is active.
    ///
    /// When the manager cannot produce a usable fix and no current location exists yet, the nearby
    /// status text is updated so the UI reflects that location is still pending or degraded.
    ///
    /// - Parameters:
    ///   - manager: The `CLLocationManager` that encountered the error.
    ///   - error: The underlying Core Location failure.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[GPS] Failed to update location: \(error.localizedDescription)")
        if currentLocation == nil {
            currentAddress = pendingLocationMessage()
        }
    }

    /// Reads the current Core Location authorization status.
    ///
    /// This small wrapper keeps status access centralized so authorization refreshes use one path.
    ///
    /// - Returns: The current `CLAuthorizationStatus` reported by Core Location.
    private func currentAuthorizationStatus() -> CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    /// Builds the status message shown while nearby location is unresolved.
    ///
    /// Reduced-accuracy mode prompts the user for Precise Location, while all other cases show a
    /// generic locating message until a usable fix is available.
    ///
    /// - Returns: The UI message describing the current pending location state.
    private func pendingLocationMessage() -> String {
        accuracyAuthorization == .reducedAccuracy
            ? "Enable Precise Location for better nearby accuracy"
            : "Locating..."
    }

    /// Persists the latest usable nearby fix for later reuse.
    ///
    /// Latitude, longitude, horizontal accuracy, and timestamp are written together so cached
    /// locations can be revalidated before the nearby feature uses them again.
    ///
    /// - Parameter location: The validated and smoothed location to store.
    private func persist(location: CLLocation) {
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: NearbyLocationStorageKey.latitude)
        defaults.set(location.coordinate.longitude, forKey: NearbyLocationStorageKey.longitude)
        defaults.set(location.horizontalAccuracy, forKey: NearbyLocationStorageKey.horizontalAccuracy)
        defaults.set(location.timestamp.timeIntervalSince1970, forKey: NearbyLocationStorageKey.timestamp)
        print("[GPS] Persisted fix: \(locationDebugDescription(for: location, now: Date()))")
    }

    /// Requests temporary precise location access when the app is in reduced-accuracy mode.
    ///
    /// A cooldown prevents repeated prompts during active nearby tracking, while the completion
    /// handler refreshes the published accuracy state after the system dialog is resolved.
    private func requestTemporaryFullAccuracyIfNeeded() {
        guard accuracyAuthorization == .reducedAccuracy else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTemporaryFullAccuracyRequestAt) >= temporaryFullAccuracyRequestCooldown else {
            return
        }

        lastTemporaryFullAccuracyRequestAt = now
        print("[GPS] Requesting temporary full-accuracy location access")
        locationManager.requestTemporaryFullAccuracyAuthorization(
            withPurposeKey: NearbyLocationPolicy.temporaryFullAccuracyPurposeKey
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.accuracyAuthorization = self.locationManager.accuracyAuthorization
                print("[GPS] Temporary accuracy request completed with accuracy=\(self.accuracyAuthorization == .fullAccuracy ? "full" : "reduced")")
                if self.currentLocation == nil {
                    self.currentAddress = self.pendingLocationMessage()
                }
            }
        }
    }

    /// Produces a smoothed nearby fix from the latest batch of accepted GPS samples.
    ///
    /// The function takes the median latitude, longitude, and horizontal accuracy across the
    /// short rolling window to reduce jitter before the location is reused elsewhere in the app.
    ///
    /// - Parameter locations: The recent accepted GPS fixes.
    /// - Returns: A smoothed `CLLocation`, or `nil` when no accepted fixes exist.
    private func medianLocation(from locations: [CLLocation]) -> CLLocation? {
        guard !locations.isEmpty else { return nil }

        let lats = locations.map { $0.coordinate.latitude }.sorted()
        let lons = locations.map { $0.coordinate.longitude }.sorted()
        let accs = locations.map(\.horizontalAccuracy).sorted()
        let freshestTimestamp = locations.map(\.timestamp).max() ?? Date()

        return CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: median(of: lats),
                longitude: median(of: lons)
            ),
            altitude: 0,
            horizontalAccuracy: median(of: accs),
            verticalAccuracy: -1,
            timestamp: freshestTimestamp
        )
    }

    /// Calculates the median value for a sorted numeric list.
    ///
    /// Odd-sized lists return the center element, while even-sized lists return the average of the
    /// two center values so the smoothing window does not bias toward one side.
    ///
    /// - Parameter values: The sorted numeric values to evaluate.
    /// - Returns: The median value for the provided list.
    private func median(of values: [Double]) -> Double {
        let mid = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[mid - 1] + values[mid]) / 2
        }
        return values[mid]
    }

    /// Formats a single GPS fix for nearby debug logging.
    ///
    /// The output includes latitude, longitude, horizontal accuracy, and age so raw and smoothed
    /// fixes can be compared quickly in the Xcode console during nearby testing.
    ///
    /// - Parameters:
    ///   - location: The `CLLocation` to describe.
    ///   - now: The reference time used to calculate fix age.
    /// - Returns: A compact one-line summary of the location fix.
    private func locationDebugDescription(for location: CLLocation, now: Date) -> String {
        let age = abs(location.timestamp.timeIntervalSince(now))
        return String(
            format: "lat=%.6f lon=%.6f acc=%.2fm age=%.2fs",
            location.coordinate.latitude,
            location.coordinate.longitude,
            location.horizontalAccuracy,
            age
        )
    }

    /// Formats a batch of GPS fixes for nearby debug logging.
    ///
    /// Each location is summarized with coordinates, accuracy, and age so filtering decisions are
    /// visible when multiple Core Location fixes arrive in the same update.
    ///
    /// - Parameters:
    ///   - locations: The GPS fixes to summarize.
    ///   - now: The reference time used to calculate fix age.
    /// - Returns: A pipe-separated description of the supplied fixes.
    private func locationDebugDescriptions(for locations: [CLLocation], now: Date) -> String {
        locations.map { locationDebugDescription(for: $0, now: now) }.joined(separator: " | ")
    }

    /// Starts reverse geocoding when the cooldown window allows it.
    ///
    /// Nearby GPS updates can be frequent, so this method throttles reverse geocoding to avoid
    /// repeatedly asking `CLGeocoder` for address updates on every accepted fix.
    ///
    /// - Parameter location: The accepted location that should be reverse geocoded.
    private func tryReverseGeocode(location: CLLocation) {
        let now = Date()
        guard now.timeIntervalSince(lastGeocodeTime) > geocodeCooldown else { return }
        lastGeocodeTime = now
        reverseGeocode(location: location)
    }

    /// Resolves a human-readable address for the current nearby location.
    ///
    /// The first placemark is converted into a compact string for the home header. When reverse
    /// geocoding fails, the UI falls back to an error message without interrupting location tracking.
    ///
    /// - Parameter location: The location to reverse geocode.
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
