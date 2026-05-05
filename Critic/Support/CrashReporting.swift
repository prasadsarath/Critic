import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum CrashReporting {
    private static var hasConfigured = false

    static func configureIfAvailable() {
        #if canImport(FirebaseCore)
        guard !hasConfigured else { return }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[Crashlytics] GoogleService-Info.plist missing. Firebase not configured.")
            return
        }

        FirebaseApp.configure()
        hasConfigured = true
        print("[Crashlytics] Firebase configured.")
        #else
        print("[Crashlytics] FirebaseCore not linked. Skipping Firebase configuration.")
        #endif
    }
}
