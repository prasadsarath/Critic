import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum CrashReporting {
    static func configureIfAvailable() {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() == nil else { return }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[Crashlytics] GoogleService-Info.plist missing. Firebase not configured.")
            return
        }

        FirebaseApp.configure()
        print("[Crashlytics] Firebase configured.")
        #else
        print("[Crashlytics] FirebaseCore not linked. Skipping Firebase configuration.")
        #endif
    }
}
