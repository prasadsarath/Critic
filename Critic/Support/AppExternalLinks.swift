import Foundation
import StoreKit
import UIKit

enum AppExternalLinks {
    static let website = URL(string: "https://veranosoft.com/")!
    static let inviteLanding = website
    static let terms = URL(string: "https://s3.us-east-1.amazonaws.com/www.veranosoft.com/critic/terms.html")!
    static let privacy = URL(string: "https://s3.us-east-1.amazonaws.com/www.veranosoft.com/critic/privacy.html")!
    static let faq = URL(string: "https://s3.us-east-1.amazonaws.com/www.veranosoft.com/critic/faq.html")!
    static let cookies = URL(string: "https://veranosoft.com/cookies")!
    static let feedback = URL(string: "https://veranosoft.com/feedback")!
    static let contactEmail = "contact@veranosoft.com"
    static let contactMailtoURL = URL(string: "mailto:\(contactEmail)")!
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
