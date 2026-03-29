import Foundation

struct FeedResponse: Codable {
    let myPosts: [PostItem]
    let receivedPosts: [PostItem]
}

struct UserLite: Codable, Equatable {
    let userId: String?
    let name: String?
    let profileUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId
        case name
        case profileUrl = "profile_url"
    }
}

struct PostItem: Codable, Identifiable, Equatable {
    var id: String { postId }

    let receiverId: String?
    let senderId: String?
    let createdAt: String?
    let poststatus: String?
    let isscheduled: Bool?
    let postId: String
    let postcontent: String
    let receiverLat: String?
    let receiverLong: String?
    let senderLat: String?
    let senderLong: String?
    let ScheduledTime: String?
    let sender: UserLite?
    let receiver: UserLite?
}

private let reviewFeedISO8601Fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let reviewFeedISO8601Basic: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private func parseDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    if let date = reviewFeedISO8601Fractional.date(from: value) ?? reviewFeedISO8601Basic.date(from: value) {
        return date
    }

    let formatter = DateFormatter()
    formatter.locale = .init(identifier: "en_US_POSIX")
    formatter.timeZone = .init(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: value)
}

@inline(__always)
private func currentReviewFeedUserId() -> String? {
    let uid = UserDefaults.standard.string(forKey: "userId")
    if uid == nil { print("⚠️ [ReviewFeed] Missing userId in UserDefaults.") }
    return uid
}

private let reviewFeedPreviewFlag: Bool = {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}()

@MainActor
final class ReviewFeedViewModel: ObservableObject {
    @Published var myPosts: [PostItem] = []
    @Published var receivedPosts: [PostItem] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var hasLoadedOnce = false

    private let listURL = AppEndpoints.Gateway.posts
    private let deleteURL = AppEndpoints.Gateway.deletePost
    private let abortURL = AppEndpoints.Gateway.deletePost
    private let reportURL = AppEndpoints.Lambda.report

    private let blockService = BlockService()

    func load() async {
        if reviewFeedPreviewFlag { return }
        guard let userId = currentReviewFeedUserId() else {
            handleMissingSession()
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let request = APIRequestDescriptor(
                url: listURL,
                queryItems: [URLQueryItem(name: "userId", value: userId)],
                authorization: .currentUser
            )
            let (data, response) = try await APIRequestExecutor.shared.perform(request)

            if !(200..<300).contains(response.statusCode) {
                let payload = String(data: data, encoding: .utf8) ?? ""
                let msg = "Server \(response.statusCode): \(payload)"
                throw NSError(domain: "Feed", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            }

            let decoded = try JSONDecoder().decode(FeedResponse.self, from: data)
            let mySorted: [PostItem] = decoded.myPosts.sorted {
                let a = parseDate($0.ScheduledTime) ?? parseDate($0.createdAt) ?? .distantPast
                let b = parseDate($1.ScheduledTime) ?? parseDate($1.createdAt) ?? .distantPast
                return a > b
            }
            let recvSorted: [PostItem] = decoded.receivedPosts.sorted {
                (parseDate($0.createdAt) ?? .distantPast) > (parseDate($1.createdAt) ?? .distantPast)
            }

            myPosts = mySorted
            receivedPosts = recvSorted
            hasLoadedOnce = true
        } catch {
            if error is CancellationError {
                return
            }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            if isMissingSession(error) {
                handleMissingSession()
                return
            }
            errorText = error.localizedDescription
            myPosts = []
            receivedPosts = []
        }
    }

    func delete(postId: String) async -> Bool {
        guard currentReviewFeedUserId() != nil else { return false }
        do {
            let request = APIRequestDescriptor(
                url: deleteURL,
                method: .DELETE,
                body: try APIRequestDescriptor.jsonBody(["postId": postId]),
                authorization: .currentUser
            )
            _ = try await APIRequestExecutor.shared.perform(request)
            await load()
            return true
        } catch {
            return false
        }
    }

    func abort(postId: String) async -> Bool {
        guard currentReviewFeedUserId() != nil else { return false }
        do {
            let url = abortURL
                .appendingPathComponent(postId)
                .appendingPathComponent("abort")
            let request = APIRequestDescriptor(
                url: url,
                method: .POST,
                body: try APIRequestDescriptor.jsonBody(["postId": postId, "op": "abort"]),
                authorization: .currentUser
            )
            _ = try await APIRequestExecutor.shared.perform(request)
            await load()
            return true
        } catch {
            return false
        }
    }

    func report(postId: String, reason: String) async -> Bool {
        guard let reporterId = currentReviewFeedUserId() else { return false }
        do {
            let payload: [String: Any] = ["postId": postId, "reason": reason, "reporterId": reporterId]
            let request = APIRequestDescriptor(
                url: reportURL,
                method: .POST,
                body: try APIRequestDescriptor.jsonBody(payload)
            )
            _ = try await APIRequestExecutor.shared.perform(request)
            return true
        } catch {
            return false
        }
    }

    func fetchReportReasons() async -> [(id: String, text: String)] {
        do {
            let request = APIRequestDescriptor(url: reportURL)
            let (data, response) = try await APIRequestExecutor.shared.perform(request)
            guard (200..<300).contains(response.statusCode) else {
                return []
            }
            if let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = outer["items"] as? [[String: Any]] {
                return items.compactMap { it in
                    let id = String(describing: it["reasonId"] ?? it["id"] ?? "")
                    let text = String(describing: it["reason"] ?? it["label"] ?? "")
                    guard !id.isEmpty, !text.isEmpty else { return nil }
                    return (id, text)
                }
            }
        } catch {}
        return []
    }

    func checkAlreadyReported(postId: String) async -> (Bool, String?) {
        guard let reporterId = currentReviewFeedUserId() else { return (false, nil) }
        do {
            let request = APIRequestDescriptor(
                url: reportURL,
                queryItems: [
                    URLQueryItem(name: "postId", value: postId),
                    URLQueryItem(name: "reporterId", value: reporterId)
                ]
            )
            let (data, _) = try await APIRequestExecutor.shared.perform(request)
            if let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let already = outer["alreadyReported"] as? Bool, already {
                    let msg = outer["message"] as? String
                    return (true, msg)
                }
            }
        } catch {}
        return (false, nil)
    }

    func blockUser(targetUserId: String, reason: String? = nil) async -> Bool {
        guard let me = currentReviewFeedUserId() else { return false }
        do {
            return try await blockService.block(blockedById: me, blockedId: targetUserId, reason: reason)
        } catch {
            return false
        }
    }

    private func isMissingSession(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "Auth" && nsError.code == 401
    }

    private func handleMissingSession() {
        errorText = nil
        myPosts = []
        receivedPosts = []
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        NotificationCenter.default.post(name: .didLogout, object: nil)
    }
}
