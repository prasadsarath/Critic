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

    private let moderationURL = AppEndpoints.Gateway.moderation
    private let postURL = AppEndpoints.Gateway.createPost

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
                body: try APIRequestDescriptor.jsonBody(body),
                authorization: .currentUser
            )
            let (data, http) = try await APIRequestExecutor.shared.perform(request)
            print("[Moderation] status=\(http.statusCode)")
            guard (200..<300).contains(http.statusCode) else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw NSError(domain: "Moderation", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: msg ?? "HTTP \(http.statusCode)"])
            }

            guard let decision = moderationDecision(from: data) else {
                print("[Moderation] unrecognized response=\(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
                reviewApproved = false
                scheduledAt = nil
                await showMessage("Moderation response was unclear. Please try again.")
                return
            }

            switch decision {
            case .approved(let replacement, let message):
                suppressTextInvalidation = true
                if let replacement {
                    reviewText = replacement
                }
                reviewApproved = true
                await showMessage(message)
            case .rejected(let message):
                reviewApproved = false
                scheduledAt = nil
                await showMessage(message)
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

    private enum ModerationDecision {
        case approved(replacement: String?, message: String)
        case rejected(message: String)
    }

    private func moderationDecision(from data: Data) -> ModerationDecision? {
        guard !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return moderationDecision(fromJSONObject: object)
        }

        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        return moderationDecision(fromText: raw)
    }

    private func moderationDecision(fromJSONObject object: Any) -> ModerationDecision? {
        if let isHateSpeech = object as? Bool {
            return isHateSpeech ? .rejected(message: moderationRejectedMessage)
                                : .approved(replacement: nil, message: moderationApprovedMessage)
        }

        if let dict = object as? [String: Any] {
            if let body = dict["body"] as? String,
               let bodyDecision = moderationDecision(fromBodyString: body) {
                return bodyDecision
            }

            if let choices = dict["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return moderationDecision(fromText: content)
            }

            if let approved = boolValue(in: dict, keys: ["approved", "allowed", "safe", "is_safe", "isSafe"]) {
                return approved ? .approved(replacement: nil, message: moderationApprovedMessage)
                                : .rejected(message: moderationRejectedMessage(from: dict))
            }

            if let flagged = boolValue(in: dict, keys: ["flagged", "blocked", "unsafe", "is_hate", "isHate", "toxic", "offensive"]) {
                return flagged ? .rejected(message: moderationRejectedMessage(from: dict))
                               : .approved(replacement: nil, message: moderationApprovedMessage)
            }

            for key in ["moderated_text", "moderatedText", "rewritten", "rewrite", "cleaned_text", "cleanedText"] {
                if let text = cleanString(dict[key]), !text.isEmpty {
                    return .approved(replacement: text, message: moderationApprovedMessage)
                }
            }

            for key in ["result", "message", "content", "text", "output", "classification", "label"] {
                if let text = cleanString(dict[key]),
                   let decision = moderationDecision(fromText: text) {
                    return decision
                }
            }
        }

        if let array = object as? [Any] {
            for item in array {
                if let decision = moderationDecision(fromJSONObject: item) {
                    return decision
                }
            }
        }

        if let text = object as? String {
            return moderationDecision(fromText: text)
        }

        return nil
    }

    private func moderationDecision(fromBodyString body: String) -> ModerationDecision? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return nil }

        if let bodyData = trimmedBody.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: bodyData, options: [.fragmentsAllowed]),
           let decision = moderationDecision(fromJSONObject: object) {
            return decision
        }

        return moderationDecision(fromText: trimmedBody)
    }

    private func moderationDecision(fromText rawText: String) -> ModerationDecision? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let normalized = text.lowercased()
        if normalized == "false" {
            return .approved(replacement: nil, message: moderationApprovedMessage)
        }
        if normalized == "true" {
            return .rejected(message: moderationRejectedMessage)
        }

        let approvedSignals = [
            "safe",
            "allowed",
            "approved",
            "not hate",
            "no hate",
            "not offensive",
            "not toxic",
            "non-toxic",
            "non toxic",
            "no violation",
            "does not violate"
        ]
        if approvedSignals.contains(where: { normalized.contains($0) }) {
            return .approved(replacement: nil, message: moderationApprovedMessage)
        }

        let rejectedSignals = [
            "hate",
            "toxic",
            "offensive",
            "blocked",
            "unsafe",
            "reject",
            "rejected",
            "violate",
            "violates",
            "modify your content",
            "not allowed"
        ]
        if rejectedSignals.contains(where: { normalized.contains($0) }) {
            return .rejected(message: text == moderationApprovedMessage ? moderationRejectedMessage : text)
        }

        if looksLikeUserContent(text) {
            return .approved(replacement: text, message: moderationApprovedMessage)
        }

        return nil
    }

    private var moderationApprovedMessage: String {
        "Looks good! You can post now or schedule within 24 hours."
    }

    private var moderationRejectedMessage: String {
        "As per guidelines, please modify your content."
    }

    private func moderationRejectedMessage(from dict: [String: Any]) -> String {
        for key in ["reason", "message", "error"] {
            if let text = cleanString(dict[key]), !text.isEmpty {
                return text
            }
        }
        return moderationRejectedMessage
    }

    private func boolValue(in dict: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dict[key] as? Bool {
                return value
            }
            if let text = cleanString(dict[key])?.lowercased() {
                if ["true", "yes", "1", "safe", "allowed", "approved"].contains(text) {
                    return true
                }
                if ["false", "no", "0", "unsafe", "blocked", "rejected"].contains(text) {
                    return false
                }
            }
        }
        return nil
    }

    private func cleanString(_ value: Any?) -> String? {
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func looksLikeUserContent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let classifierWords = ["safe", "allowed", "approved", "clean", "pass", "passed", "ok", "okay"]
        return text.count > 12 && !classifierWords.contains(normalized)
    }

    private func showMessage(_ text: String) async {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        validationMessage = text
        showValidationAlert = true
    }
}
