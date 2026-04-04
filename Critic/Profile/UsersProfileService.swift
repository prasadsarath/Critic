import Foundation

struct UsersTableProfile: Decodable, Equatable {
    let userId: String?
    let name: String?
    let displayName: String?
    let aliasname: String?
    let email: String?
    let phone: String?
    let bio: String?
    let profileURL: String?
    let avatarUrl: String?
    let timestamp: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId
        case name
        case displayName
        case aliasname
        case email
        case phone
        case bio
        case profileURL = "profile_url"
        case avatarUrl
        case timestamp
        case createdAt
        case updatedAt
    }
}

private struct UsersMeEnvelope: Decodable {
    let ok: Bool?
    let fromUsersTable: Bool?
    let user: UsersTableProfile?
}

private struct UsersGetEnvelope: Decodable {
    let ok: Bool?
    let user: UsersTableProfile?
}

private struct UsersUpdateEnvelope: Decodable {
    let ok: Bool?
    let user: UsersTableProfile?
}

private struct AvatarUploadEnvelope: Decodable {
    let ok: Bool?
    let uploadUrl: String?
    let fileURL: String?
    let profileURL: String?
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case uploadUrl
        case fileURL
        case profileURL = "profile_url"
        case contentType
    }
}

struct AvatarUploadTarget {
    let uploadURL: URL
    let fileURL: String
    let contentType: String
}

struct FeedbackSubmission: Decodable, Equatable {
    let id: String?
    let submissionId: String?
    let message: String?
    let text: String?
    let feedback: String?
    let status: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case submissionId
        case message
        case text
        case feedback
        case status
        case createdAt
        case updatedAt
    }

    var resolvedID: String {
        if let id, !id.isEmpty { return id }
        if let submissionId, !submissionId.isEmpty { return submissionId }
        if let createdAt, !createdAt.isEmpty { return createdAt }
        return messageText
    }

    var messageText: String {
        let resolved = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? text?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? feedback?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolved, !resolved.isEmpty else { return "Feedback submission" }
        return resolved
    }

    var statusText: String {
        let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Submitted" }
        return trimmed.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct FeedbackSubmitEnvelope: Decodable {
    let ok: Bool?
    let submission: FeedbackSubmission?
    let item: FeedbackSubmission?
}

private struct FeedbackListEnvelope: Decodable {
    let ok: Bool?
    let submissions: [FeedbackSubmission]?
    let items: [FeedbackSubmission]?
}

enum UsersProfileService {
    static func fetchMe() async throws -> UsersTableProfile {
        let request = APIRequestDescriptor(
            url: AppEndpoints.Gateway.usersMe,
            authorization: .currentUser
        )
        print("[UsersProfileService] request: GET \(AppEndpoints.Gateway.usersMe.absoluteString)")
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        print("[UsersProfileService] users_me status=\(response.statusCode)")
        print("[UsersProfileService] users_me body=\(bodyText)")

        guard (200...299).contains(response.statusCode) else {
            throw APIError.statusCode(response.statusCode, data)
        }

        let responseEnvelope = try JSONDecoder().decode(UsersMeEnvelope.self, from: data)
        guard let user = responseEnvelope.user else {
            throw APIError.invalidResponse
        }
        print(
            "[UsersProfileService] users_me decoded userId=\(user.userId ?? "nil") " +
            "name=\(user.name ?? user.displayName ?? user.aliasname ?? "nil") " +
            "email=\(user.email ?? "nil")"
        )
        cacheCurrentUser(user)
        return user
    }

    static func fetchUser(userId: String) async throws -> UsersTableProfile {
        let request = APIRequestDescriptor(
            url: AppEndpoints.Gateway.usersGet,
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            authorization: .currentUser
        )
        print("[UsersProfileService] request: GET \(AppEndpoints.Gateway.usersGet.absoluteString)?userId=\(userId)")
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        print("[UsersProfileService] users_get status=\(response.statusCode) targetUserId=\(userId)")
        print("[UsersProfileService] users_get body=\(bodyText)")

        guard (200...299).contains(response.statusCode) else {
            throw APIError.statusCode(response.statusCode, data)
        }

        let responseEnvelope = try JSONDecoder().decode(UsersGetEnvelope.self, from: data)
        guard let user = responseEnvelope.user else {
            throw APIError.invalidResponse
        }
        print(
            "[UsersProfileService] users_get decoded targetUserId=\(userId) " +
            "resolvedUserId=\(user.userId ?? "nil") " +
            "name=\(user.name ?? user.displayName ?? user.aliasname ?? "nil") " +
            "email=\(user.email ?? "nil")"
        )
        cacheUser(user)
        return user
    }

    static func updateCurrentUser(
        name: String,
        bio: String,
        profileURL: String? = nil,
        reason: String = "edit_profile"
    ) async throws -> UsersTableProfile {
        var payload: [String: String] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "bio": bio,
            "reason": reason
        ]
        if let profileURL = normalized(profileURL) {
            payload["profile_url"] = profileURL
        }

        let request = APIRequestDescriptor(
            url: AppEndpoints.Gateway.usersUpdate,
            method: .POST,
            body: try APIRequestDescriptor.jsonBody(payload),
            authorization: .currentUser
        )

        print("[UsersProfileService] request: POST \(AppEndpoints.Gateway.usersUpdate.absoluteString)")
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        print("[UsersProfileService] users_update status=\(response.statusCode)")
        print("[UsersProfileService] users_update body=\(bodyText)")

        guard (200...299).contains(response.statusCode) else {
            throw APIError.statusCode(response.statusCode, data)
        }

        let responseEnvelope = try JSONDecoder().decode(UsersUpdateEnvelope.self, from: data)
        guard let user = responseEnvelope.user else {
            throw APIError.invalidResponse
        }
        cacheCurrentUser(user)
        print(
            "[UsersProfileService] users_update decoded userId=\(user.userId ?? "nil") " +
            "name=\(user.name ?? user.displayName ?? user.aliasname ?? "nil") " +
            "bio=\(user.bio ?? "nil") profileURL=\(user.profileURL ?? user.avatarUrl ?? "nil")"
        )
        return user
    }

    static func requestAvatarUploadTarget(contentType: String) async throws -> AvatarUploadTarget {
        let request = APIRequestDescriptor(
            url: AppEndpoints.Gateway.profileAvatarUploadURL,
            method: .POST,
            body: try APIRequestDescriptor.jsonBody(["contentType": contentType]),
            authorization: .currentUser
        )

        print("[UsersProfileService] request: POST \(AppEndpoints.Gateway.profileAvatarUploadURL.absoluteString)")
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        print("[UsersProfileService] avatar_upload_url status=\(response.statusCode)")
        print("[UsersProfileService] avatar_upload_url body=\(bodyText)")

        guard (200...299).contains(response.statusCode) else {
            throw APIError.statusCode(response.statusCode, data)
        }

        let envelope = try JSONDecoder().decode(AvatarUploadEnvelope.self, from: data)
        guard
            let uploadURLString = normalized(envelope.uploadUrl),
            let uploadURL = URL(string: uploadURLString),
            let fileURL = normalized(envelope.profileURL) ?? normalized(envelope.fileURL)
        else {
            throw APIError.invalidResponse
        }

        return AvatarUploadTarget(
            uploadURL: uploadURL,
            fileURL: fileURL,
            contentType: normalized(envelope.contentType) ?? contentType
        )
    }

    static func uploadAvatarData(
        _ data: Data,
        using target: AvatarUploadTarget
    ) async throws {
        var request = URLRequest(url: target.uploadURL)
        request.httpMethod = HTTPMethod.PUT.rawValue
        request.setValue(target.contentType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        print("[UsersProfileService] avatar_upload PUT status=\(http.statusCode) url=\(target.uploadURL.absoluteString)")
        guard (200...299).contains(http.statusCode) else {
            throw APIError.statusCode(http.statusCode, nil)
        }
    }

    static func meUser(from profile: UsersTableProfile) -> MeUser {
        MeUser(
            userId: normalized(profile.userId),
            name: resolvedDisplayName(from: profile),
            nickname: normalized(profile.aliasname),
            profession: nil,
            bio: normalized(profile.bio),
            createdAt: normalized(profile.createdAt),
            updatedAt: normalized(profile.updatedAt)
        )
    }

    static func meIdentity(from profile: UsersTableProfile) -> MeIdentity {
        MeIdentity(
            sub: normalized(profile.userId),
            phoneNumber: normalized(profile.phone),
            email: normalized(profile.email),
            cognitoUsername: nil,
            preferredUsername: nil,
            nickname: normalized(profile.aliasname),
            name: resolvedDisplayName(from: profile),
            givenName: nil,
            familyName: nil,
            emailVerified: nil,
            phoneNumberVerified: nil
        )
    }

    static func merge(_ profile: UsersTableProfile, onto fallback: UserLocation) -> UserLocation {
        let resolvedName = resolvedDisplayName(from: profile) ?? fallback.displayName
        return UserLocation(
            id: normalized(profile.userId) ?? fallback.id,
            latitude: fallback.latitude,
            longitude: fallback.longitude,
            profileImageName: fallback.profileImageName,
            displayName: resolvedName,
            email: normalized(profile.email) ?? fallback.email,
            phone: normalized(profile.phone) ?? fallback.phone,
            profileUrl: resolvedProfileURL(from: profile) ?? fallback.profileUrl,
            distanceMeters: fallback.distanceMeters,
            isSimulated: fallback.isSimulated
        )
    }

    static func cacheCurrentUser(_ profile: UsersTableProfile) {
        let defaults = UserDefaults.standard
        if let userId = normalized(profile.userId) {
            defaults.set(userId, forKey: "userId")
        }
        if let name = resolvedDisplayName(from: profile) {
            defaults.set(name, forKey: "userName")
        }
        if let email = normalized(profile.email) {
            defaults.set(email, forKey: "userEmail")
        }
        if let phone = normalized(profile.phone) {
            defaults.set(phone, forKey: "userPhone")
        }
        if let profileURL = resolvedProfileURL(from: profile) {
            defaults.set(profileURL, forKey: "userProfileUrl")
        } else {
            defaults.removeObject(forKey: "userProfileUrl")
        }
        cacheUser(profile)
    }

    static func cacheUser(_ profile: UsersTableProfile) {
        KnownUserDirectory.remember(
            userId: normalized(profile.userId),
            displayName: resolvedDisplayName(from: profile),
            email: normalized(profile.email),
            phone: normalized(profile.phone),
            profileUrl: resolvedProfileURL(from: profile)
        )
    }

    private static func resolvedDisplayName(from profile: UsersTableProfile) -> String? {
        let userId = normalized(profile.userId)
        let name = normalized(profile.name) ?? normalized(profile.displayName)
        return DisplayNameResolver.preferredName(name, userId: userId)
            ?? DisplayNameResolver.preferredName(profile.aliasname, userId: userId)
            ?? displayNameFromEmail(profile.email)
            ?? displayNameFromPhone(profile.phone)
    }

    private static func resolvedProfileURL(from profile: UsersTableProfile) -> String? {
        normalized(profile.profileURL) ?? normalized(profile.avatarUrl)
    }

    private static func displayNameFromEmail(_ email: String?) -> String? {
        guard let email = normalized(email),
              let local = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first else {
            return nil
        }
        return DisplayNameResolver.preferredName(String(local), userId: nil)
    }

    private static func displayNameFromPhone(_ phone: String?) -> String? {
        guard let phone = normalized(phone) else { return nil }
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 4 else { return nil }
        return String(digits.suffix(min(4, digits.count)))
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum FeedbackService {
    static func submit(message: String) async throws -> FeedbackSubmission? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.invalidRequest
        }

        let request = APIRequestDescriptor(
            url: AppEndpoints.Gateway.feedbackSubmit,
            method: .POST,
            body: try APIRequestDescriptor.jsonBody([
                "message": trimmed,
                "source": "ios_settings_feedback"
            ]),
            authorization: .currentUser
        )

        print("[FeedbackService] request: POST \(AppEndpoints.Gateway.feedbackSubmit.absoluteString)")
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        print("[FeedbackService] submit status=\(response.statusCode)")
        print("[FeedbackService] submit body=\(bodyText)")

        guard (200...299).contains(response.statusCode) else {
            throw APIError.statusCode(response.statusCode, data)
        }

        let envelope = try JSONDecoder().decode(FeedbackSubmitEnvelope.self, from: data)
        let submission = envelope.submission ?? envelope.item
        print("[FeedbackService] submit decoded id=\(submission?.resolvedID ?? "nil") status=\(submission?.statusText ?? "Submitted")")
        return submission
    }

    static func fetchSubmissions() async throws -> [FeedbackSubmission] {
        let request = APIRequestDescriptor(
            url: AppEndpoints.Gateway.feedbackSubmissions,
            authorization: .currentUser
        )

        print("[FeedbackService] request: GET \(AppEndpoints.Gateway.feedbackSubmissions.absoluteString)")
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        print("[FeedbackService] submissions status=\(response.statusCode)")
        print("[FeedbackService] submissions body=\(bodyText)")

        guard (200...299).contains(response.statusCode) else {
            throw APIError.statusCode(response.statusCode, data)
        }

        let envelope = try JSONDecoder().decode(FeedbackListEnvelope.self, from: data)
        let submissions = envelope.submissions ?? envelope.items ?? []
        print("[FeedbackService] submissions decoded count=\(submissions.count)")
        return submissions
    }
}
