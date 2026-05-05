import Foundation
import StoreKit
import UIKit

enum AppExternalLinks {
    static let website = URL(string: "https://veranosoft.com/")!
    static let inviteLanding = website
    static let terms = URL(string: "https://www.veranosoft.com/critic/terms.html")!
    static let privacy = URL(string: "https://www.veranosoft.com/critic/privacy.html")!
    static let faq = URL(string: "https://www.veranosoft.com/critic/faq.html")!
    static let cookies = URL(string: "https://veranosoft.com/cookies")!
    static let feedback = URL(string: "https://www.veranosoft.com/feedback.html")!
    static let contactEmail = "contact@veranosoft.com"
    static let contactMailtoURL = URL(string: "mailto:\(contactEmail)")!

    static func contactMailtoURL(subject: String, body: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = contactEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url ?? contactMailtoURL
    }
}

enum AppReviewRequester {
    @MainActor
    static func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        SKStoreReviewController.requestReview(in: scene)
    }
}
