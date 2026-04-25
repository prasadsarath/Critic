import Foundation

struct FeedResponse: Codable {
    let myPosts: [PostItem]
    let receivedPosts: [PostItem]
}

struct UserLite: Codable, Equatable {
    let userId: String?
    let name: String?
    let phone: String?
    let profileUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId
        case name
        case phone
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

private let reviewFeedDebugLoggingEnabled = true

private func reviewFeedPrettyJSONString(from data: Data) -> String? {
    guard
        let object = try? JSONSerialization.jsonObject(with: data),
        let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
        let string = String(data: formatted, encoding: .utf8)
    else {
        return String(data: data, encoding: .utf8)
    }

    return string
}

private func reviewFeedPostSummary(_ item: PostItem, bucket: String, index: Int) -> String {
    let senderId = item.sender?.userId ?? item.senderId ?? "nil"
    let senderName = item.sender?.name ?? "nil"
    let receiverId = item.receiver?.userId ?? item.receiverId ?? "nil"
    let receiverName = item.receiver?.name ?? "nil"
    let content = item.postcontent.replacingOccurrences(of: "\n", with: " ")

    return """
    [ReviewFeed][\(bucket)][\(index)] postId=\(item.postId) \
    senderId=\(senderId) senderName=\(senderName) \
    receiverId=\(receiverId) receiverName=\(receiverName) \
    createdAt=\(item.createdAt ?? "nil") scheduledAt=\(item.ScheduledTime ?? "nil") \
    content=\"\(content)\"
    """
}

@MainActor
final class ReviewFeedViewModel: ObservableObject {
    @Published var myPosts: [PostItem] = []
    @Published var receivedPosts: [PostItem] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var hasLoadedOnce = false

    private var isFetching = false

    private let listURL = AppEndpoints.Gateway.posts
    private let deleteURL = AppEndpoints.Gateway.deletePost
    private let abortURL = AppEndpoints.Gateway.deletePost
    private let reportURL = AppEndpoints.Lambda.report

    private let blockService = BlockService()

    func load(showSpinner: Bool = true) async {
        if reviewFeedPreviewFlag { return }
        if isFetching { return }
        guard let userId = currentReviewFeedUserId() else {
            handleMissingSession()
            return
        }

        isFetching = true
        if showSpinner {
            isLoading = true
            errorText = nil
        }
        defer {
            isFetching = false
            if showSpinner {
                isLoading = false
            }
        }

        do {
            let request = APIRequestDescriptor(
                url: listURL,
                queryItems: [URLQueryItem(name: "userId", value: userId)],
                authorization: .currentUser
            )
            if reviewFeedDebugLoggingEnabled {
                let storedName = UserDefaults.standard.string(forKey: "userName") ?? "nil"
                let storedEmail = UserDefaults.standard.string(forKey: "userEmail") ?? "nil"
                print("[ReviewFeed] GET \(listURL.absoluteString)?userId=\(userId)")
                print("[ReviewFeed] current identity userId=\(userId) userName=\(storedName) userEmail=\(storedEmail)")
            }
            let (data, response) = try await APIRequestExecutor.shared.perform(request)
            if reviewFeedDebugLoggingEnabled {
                print("[ReviewFeed] response status=\(response.statusCode)")
                if let raw = reviewFeedPrettyJSONString(from: data) {
                    print("[ReviewFeed] raw response:\n\(raw)")
                } else {
                    print("[ReviewFeed] raw response: <non-utf8 \(data.count) bytes>")
                }
            }

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

            KnownUserDirectory.rememberCurrentUserFromDefaults()
            (mySorted + recvSorted).forEach { item in
                KnownUserDirectory.remember(
                    userId: item.sender?.userId ?? item.senderId,
                    displayName: item.sender?.name,
                    email: nil,
                    phone: item.sender?.phone,
                    profileUrl: item.sender?.profileUrl
                )
                KnownUserDirectory.remember(
                    userId: item.receiver?.userId ?? item.receiverId,
                    displayName: item.receiver?.name,
                    email: nil,
                    phone: item.receiver?.phone,
                    profileUrl: item.receiver?.profileUrl
                )
            }

            myPosts = mySorted
            receivedPosts = recvSorted
            errorText = nil
            hasLoadedOnce = true
            if reviewFeedDebugLoggingEnabled {
                print("[ReviewFeed] decoded myPosts=\(mySorted.count) receivedPosts=\(recvSorted.count)")
                mySorted.enumerated().forEach { index, item in
                    print(reviewFeedPostSummary(item, bucket: "myPosts", index: index))
                }
                recvSorted.enumerated().forEach { index, item in
                    print(reviewFeedPostSummary(item, bucket: "receivedPosts", index: index))
                }
            }
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
            if showSpinner || !hasLoadedOnce {
                errorText = error.localizedDescription
                myPosts = []
                receivedPosts = []
            } else if reviewFeedDebugLoggingEnabled {
                print("[ReviewFeed] background refresh failed: \(error.localizedDescription)")
            }
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
