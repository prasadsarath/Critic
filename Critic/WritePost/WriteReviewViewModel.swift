import Foundation
import UserNotifications
import UIKit

@inline(__always)
private func currentWriteUserId() -> String? {
    let uid = UserDefaults.standard.string(forKey: "userId")
    if uid == nil { print("⚠️ [Write] Missing userId in UserDefaults") }
    return uid
}

struct PostPayload: Codable {
    var postId: String
    var createdAt: String
    var isscheduled: Bool
    var postcontent: String
    var poststatus: String
    var receiverId: String?
    var receiverLat: String?
    var receiverLong: String?
    var ScheduledTime: String?
    var senderId: String
    var senderLat: String?
    var senderLong: String?

    static func make(
        content: String,
        receiverId: String?,
        scheduledAt: Date? = nil,
        senderId: String = (UserDefaults.standard.string(forKey: "userId") ?? "")
    ) -> PostPayload {
        let iso = ISO8601DateFormatter()
        return .init(
            postId: UUID().uuidString,
            createdAt: iso.string(from: Date()),
            isscheduled: scheduledAt != nil,
            postcontent: content,
            poststatus: scheduledAt == nil ? "1" : "0",
            receiverId: receiverId,
            receiverLat: nil,
            receiverLong: nil,
            ScheduledTime: scheduledAt.map { iso.string(from: $0) },
            senderId: senderId,
            senderLat: nil,
            senderLong: nil
        )
    }
}

@MainActor
final class WriteReviewViewModel: ObservableObject {
    @Published var reviewText = ""
    @Published var isModerating = false
    @Published var isPosting = false
    @Published var reviewApproved = false
    @Published var validationMessage = ""
    @Published var showValidationAlert = false
    @Published var showPostSheet = false
    @Published var scheduleDate = Date().addingTimeInterval(60 * 5)
    @Published var scheduledAt: Date?

    private let navigationManager: NavigationManager
    private var suppressTextInvalidation = false

    private let moderationURL = AppEndpoints.Lambda.moderation
    private let postURL = AppEndpoints.Lambda.post

    init(navigationManager: NavigationManager? = nil) {
        self.navigationManager = navigationManager ?? NavigationManager.shared
    }

    private var selectedUser: UserLocation? {
        navigationManager.selectedUser.map(KnownUserDirectory.hydrated)
    }

    var targetUserName: String {
        guard let selectedUser else { return "User" }
        return resolvedUserDisplayName(selectedUser)
    }

    var targetUserId: String? {
        selectedUser?.id
    }

    var targetUserImageSymbol: String {
        selectedUser?.profileImageName ?? "person.circle.fill"
    }

    var targetUserAvatarURL: String? {
        selectedUser?.profileUrl ?? KnownUserDirectory.profileUrl(for: selectedUser?.id)
    }

    var targetUserSeed: String? {
        selectedUser.map(resolvedUserSeed) ?? targetUserId
    }

    var targetDistanceText: String? {
        guard let selectedUser else { return nil }
        guard let meters = liveDistanceMeters(
            to: selectedUser,
            fallback: navigationManager.selectedDistance ?? selectedUser.distanceMeters
        ) else { return nil }
        return String(format: "%.1f meters away", meters)
    }

    var trimmed: String {
        reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedCount: Int {
        trimmed.count
    }

    var canReview: Bool {
        trimmedCount > 5 && !isModerating && !reviewApproved
    }

    var canPostNow: Bool {
        reviewApproved && !isPosting && resolvedTargetUserId != nil
    }

    var canSchedule: Bool {
        reviewApproved && !isPosting && resolvedTargetUserId != nil
    }

    var minSchedule: Date {
        Date().addingTimeInterval(60)
    }

    var maxSchedule: Date {
        Date().addingTimeInterval(60 * 60 * 24)
    }

    func handleReviewTextChanged() {
        if suppressTextInvalidation {
            suppressTextInvalidation = false
        } else {
            reviewApproved = false
            scheduledAt = nil
        }
    }

    func prepareScheduleSheet() {
        scheduleDate = clamp(date: scheduleDate, min: minSchedule, max: maxSchedule)
        showPostSheet = true
    }

    func dismissScheduleSheet() {
        showPostSheet = false
    }

    func confirmScheduleSheet() async {
        let when = clamp(date: scheduleDate, min: minSchedule, max: maxSchedule)
        showPostSheet = false
        await scheduleNow(at: when)
    }

    func handleTick() async {
        guard let when = scheduledAt, reviewApproved, !isPosting else { return }
        if Date() >= when {
            await postScheduled(at: when)
        }
    }

    func runModeration() async {
        guard trimmedCount > 5 else {
            await showMessage("Please enter at least 5 characters to review.")
            return
        }

        isModerating = true
        defer { isModerating = false }

        do {
            let body: [String: String] = ["user_input": trimmed]

            print("[Moderation] POST \(moderationURL.absoluteString)")
            let request = APIRequestDescriptor(
                url: moderationURL,
                method: .POST,
                body: try APIRequestDescriptor.jsonBody(body)
            )
            let (data, http) = try await APIRequestExecutor.shared.perform(request)
            print("[Moderation] status=\(http.statusCode)")
            guard (200..<300).contains(http.statusCode) else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw NSError(domain: "Moderation", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: msg ?? "HTTP \(http.statusCode)"])
            }

            struct ChatMessage: Codable { let content: String? }
            struct ChatChoice: Codable { let message: ChatMessage? }
            struct ChatResponse: Codable { let choices: [ChatChoice]? }

            let chat = try? JSONDecoder().decode(ChatResponse.self, from: data)
            let moderated = chat?.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let text = moderated, !text.isEmpty {
                suppressTextInvalidation = true
                reviewText = text
                reviewApproved = true
                await showMessage("Looks good! You can post now or schedule within 24 hours.")
            } else {
                reviewApproved = false
                scheduledAt = nil
                await showMessage("As per guidelines, please modify your content.")
            }
        } catch {
            reviewApproved = false
            scheduledAt = nil
            await showMessage("Moderation failed: \(error.localizedDescription)")
        }
    }

    func postNow() async {
        guard reviewApproved else {
            await showMessage("Please pass moderation before posting.")
            return
        }
        guard let uid = currentWriteUserId(), !uid.isEmpty else {
            await showMessage("Please sign in again.")
            return
        }
        let text = trimmed
        guard !text.isEmpty else {
            await showMessage("Please enter some text before posting.")
            return
        }
        guard let recipientUserId = await requireTargetUserId() else { return }

        isPosting = true
        defer { isPosting = false }

        do {
            var payload = PostPayload.make(content: text, receiverId: recipientUserId, scheduledAt: nil)
            payload.senderId = uid
            try await sendPost(payload: payload)
            notifyReviewFeedRefresh()
            navigateToPostedFeed()
            reviewText = ""
            reviewApproved = false
            scheduledAt = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Task { await self.showMessage("Posted successfully.") }
            }
        } catch {
            await showMessage("Post failed: \(error.localizedDescription)")
        }
    }

    private func scheduleNow(at when: Date) async {
        guard reviewApproved else {
            await showMessage("Please pass moderation before scheduling.")
            return
        }
        guard let uid = currentWriteUserId(), !uid.isEmpty else {
            await showMessage("Please sign in again.")
            return
        }
        let text = trimmed
        guard !text.isEmpty else {
            await showMessage("Please enter some text before scheduling.")
            return
        }
        guard let recipientUserId = await requireTargetUserId() else { return }

        isPosting = true
        defer { isPosting = false }

        do {
            var payload = PostPayload.make(content: text, receiverId: recipientUserId, scheduledAt: when)
            payload.senderId = uid
            try await sendPost(payload: payload)
            notifyReviewFeedRefresh()
            navigateToPostedFeed()
            reviewText = ""
            reviewApproved = false
            scheduledAt = nil
            await notifyScheduled(at: when)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Task { await self.showMessage("Scheduled successfully for \(when.formatted(date: .abbreviated, time: .shortened)).") }
            }
        } catch {
            await showMessage("Scheduling failed: \(error.localizedDescription)")
        }
    }

    private func postScheduled(at when: Date) async {
        guard reviewApproved, let dueAt = scheduledAt, abs(when.timeIntervalSince(dueAt)) < 1.1 else { return }
        guard let uid = currentWriteUserId(), !uid.isEmpty else { return }
        let text = trimmed
        guard !text.isEmpty else {
            await showMessage("Scheduled post aborted: text is empty.")
            scheduledAt = nil
            return
        }
        guard let recipientUserId = await requireTargetUserId() else {
            scheduledAt = nil
            return
        }

        isPosting = true
        defer { isPosting = false }

        do {
            var payload = PostPayload.make(content: text, receiverId: recipientUserId, scheduledAt: when)
            payload.senderId = uid
            try await sendPost(payload: payload)
            notifyReviewFeedRefresh()
            navigateToPostedFeed()
            reviewText = ""
            reviewApproved = false
            scheduledAt = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Task { await self.showMessage("Scheduled post delivered.") }
            }
        } catch {
            await showMessage("Scheduled post failed: \(error.localizedDescription)")
        }
    }

    private func sendPost(payload: PostPayload) async throws {
        print("[Post] POST \(postURL.absoluteString) senderId=\(payload.senderId) receiverId=\(payload.receiverId ?? "nil") scheduled=\(payload.isscheduled)")
        let request = APIRequestDescriptor(
            url: postURL,
            method: .POST,
            body: try APIRequestDescriptor.jsonBody(payload),
            authorization: .currentUser
        )
        let (data, http) = try await APIRequestExecutor.shared.perform(request)
        print("[Post] status=\(http.statusCode)")
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "Post", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "HTTP \(http.statusCode)"])
        }
    }

    private func clamp(date: Date, min: Date, max: Date) -> Date {
        if date < min { return min }
        if date > max { return max }
        return date
    }

    private var resolvedTargetUserId: String? {
        guard let raw = targetUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private func requireTargetUserId() async -> String? {
        guard let targetUserId = resolvedTargetUserId else {
            print("[Post] blocked: missing receiverId for selected user \(String(describing: selectedUser))")
            await showMessage("Couldn’t determine who this review is for. Please go back and select the user again.")
            return nil
        }
        return targetUserId
    }

    private func notifyReviewFeedRefresh() {
        NotificationCenter.default.post(name: .reviewFeedNeedsRefresh, object: nil)
    }

    private func navigateToPostedFeed() {
        NotificationCenter.default.post(name: .jumpToPosted, object: nil)
        UserDefaults.standard.set("posted", forKey: "inboxStartTab")
        NavigationManager.shared.showInbox = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NavigationManager.shared.showWritePost = false
        }
    }

    private func notifyScheduled(at date: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return
        @unknown default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Post Scheduled"
        content.body = "Your comment will be sent at \(date.formatted(date: .abbreviated, time: .shortened))."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func showMessage(_ text: String) async {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        validationMessage = text
        showValidationAlert = true
    }
}
