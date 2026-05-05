import Foundation
import PostHog

enum PostHogAnalytics {
    static let analyticsEnabledKey = "posthog_analytics_enabled"

    private static let projectAPIKey = "phc_wpp42yiTWkxCCkqwSCcmbA6mg8auZCWZQpfJ5HFRczxF"
    private static let host = "https://us.i.posthog.com"
    private static var hasConfigured = false

    static func configure() {
        guard !hasConfigured else { return }

        let config = PostHogConfig(projectToken: projectAPIKey, host: host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true
        config.captureElementInteractions = false
        config.optOut = !isAnalyticsEnabled
        if #available(iOS 15.0, *) {
            config.surveys = false
        }
        config.sessionReplay = true
        config.sessionReplayConfig.maskAllImages = true
        config.sessionReplayConfig.maskAllTextInputs = true
        config.sessionReplayConfig.screenshotMode = true
        config.sessionReplayConfig.captureNetworkTelemetry = false
        config.sessionReplayConfig.sampleRate = 1.0

        PostHogSDK.shared.setup(config)
        hasConfigured = true
        identifyCurrentUserIfAvailable()
    }

    static var isAnalyticsEnabled: Bool {
        if UserDefaults.standard.object(forKey: analyticsEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: analyticsEnabledKey)
    }

    static func setAnalyticsEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: analyticsEnabledKey)
        guard hasConfigured else { return }

        if isEnabled {
            PostHogSDK.shared.optIn()
            identifyCurrentUserIfAvailable()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    static func identifyCurrentUserIfAvailable() {
        guard hasConfigured else { return }
        guard let userId = normalized(UserDefaults.standard.string(forKey: "userId")) else { return }
        PostHogSDK.shared.identify(userId)
    }

    static func reset() {
        guard hasConfigured else { return }
        PostHogSDK.shared.reset()
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
