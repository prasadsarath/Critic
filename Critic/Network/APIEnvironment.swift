import Foundation

enum AppEndpoints {
    enum Auth {
        static let issuer = URL(string: "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_lpHu3UDYg")!
        static let clientID = "7mokregcmnho93vluph4eh21fj"
        static let redirectURI = URL(string: "criticapp://callback")!
        static let logoutRedirectURI = URL(string: "criticapp://callback")!
    }

    enum Gateway {
        private static let baseURL = URL(string: "https://gkhdzpiwx7.execute-api.us-east-1.amazonaws.com")!

        static let posts = baseURL.appendingPathComponent("getposts")
        static let deletePost = baseURL.appendingPathComponent("DeletePost")
        static let contactsLookup = baseURL.appendingPathComponent("critic_contacts_lookup")
        static let tagging = baseURL.appendingPathComponent("critic_tagfunction")
        static let blocking = baseURL.appendingPathComponent("critic_blockusersfunction")
    }

    enum Lambda {
        static let report = URL(string: "https://lj5i5ptax6onan63mh5zdjcdle0rjnbn.lambda-url.us-east-1.on.aws/")!
        static let moderation = URL(string: "https://4wesg5vzijd7teibdbjm7bvsnm0lgyhz.lambda-url.us-east-1.on.aws/")!
        static let post = URL(string: "https://jxqfllzoasbqj3klvnvzdtrfne0aeyit.lambda-url.us-east-1.on.aws/")!
        static let me = URL(string: "https://a3uam55nakm5yxffpwdzxxnau40zgxjt.lambda-url.us-east-1.on.aws/me")!
        static let cognitoProfile = URL(string: "https://j2mgqu6gohzcpr3bpt5qwuctle0ynpyh.lambda-url.us-east-1.on.aws/")!
    }

    enum Realtime {
        static let webSocket = URL(string: "wss://xrry9op8xl.execute-api.us-east-1.amazonaws.com/production/")!
    }
}
