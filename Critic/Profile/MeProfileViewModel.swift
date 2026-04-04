import Foundation

enum CognitoProfileError: LocalizedError {
    case missingRequiredScope(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredScope(let scope):
            return "Access token is missing \(scope). Enable that scope on the Cognito app client to use the direct profile Lambda."
        }
    }
}

struct DirectCognitoProfileResponse: Decodable {
    let message: String?
    let profile: DirectCognitoProfile?
    let attributes: [String: String]?
}

struct DirectCognitoProfile: Decodable, Equatable {
    let name: String?
    let givenName: String?
    let familyName: String?
    let email: String?
    let phone: String?
    let sub: String?
    let preferredUsername: String?

    enum CodingKeys: String, CodingKey {
        case name
        case givenName
        case familyName
        case email
        case phone
        case sub
        case preferredUsername = "preferred_username"
    }
}

struct MeUser: Decodable, Equatable {
    let userId: String?
    let name: String?
    let nickname: String?
    let profession: String?
    let bio: String?
    let createdAt: String?
    let updatedAt: String?
}

struct MeIdentity: Decodable, Equatable {
    let sub: String?
    let phoneNumber: String?
    let email: String?
    let cognitoUsername: String?
    let preferredUsername: String?
    let nickname: String?
    let name: String?
    let givenName: String?
    let familyName: String?
    let emailVerified: Bool?
    let phoneNumberVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case sub
        case phoneNumber = "phone_number"
        case email
        case cognitoUsername = "cognito_username"
        case preferredUsername = "preferred_username"
        case nickname
        case name
        case givenName = "given_name"
        case familyName = "family_name"
        case emailVerified = "email_verified"
        case phoneNumberVerified = "phone_number_verified"
    }
}

enum CognitoDirectProfileService {
    private static let profileURL = AppEndpoints.Lambda.cognitoProfile
    private static let requiredScope = "aws.cognito.signin.user.admin"

    static func fetchForCurrentUser() async throws -> DirectCognitoProfileResponse {
        let accessToken = try await OIDCAuthManager.shared.getAccessToken()
        return try await fetch(accessToken: accessToken)
    }

    static func fetch(accessToken: String) async throws -> DirectCognitoProfileResponse {
        guard hasRequiredScope(accessToken) else {
            throw CognitoProfileError.missingRequiredScope(requiredScope)
        }

        let request = APIRequestDescriptor(
            url: profileURL,
            method: .POST,
            body: try APIRequestDescriptor.jsonBody(["accessToken": accessToken])
        )

        print("[CognitoProfile] request: POST \(profileURL.absoluteString)")
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        print("[CognitoProfile] status=\(response.statusCode)")
        print("[CognitoProfile] body=\(bodyText)")

        guard (200...299).contains(response.statusCode) else {
            throw APIError.statusCode(response.statusCode, data)
        }

        let decoded = try JSONDecoder().decode(DirectCognitoProfileResponse.self, from: data)
        cache(decoded)
        return decoded
    }

    static func user(from response: DirectCognitoProfileResponse) -> MeUser? {
        let resolvedIdentity = identity(from: response)
        let resolvedName = normalizedDisplayName(
            response.profile?.name ?? attribute("name", in: response),
            userId: resolvedIdentity?.sub
        ) ?? normalizedDisplayName(
            combinedName(
                givenName: response.profile?.givenName ?? attribute("given_name", in: response),
                familyName: response.profile?.familyName ?? attribute("family_name", in: response)
            ),
            userId: resolvedIdentity?.sub
        )
        let nickname = normalizedDisplayName(attribute("nickname", in: response), userId: resolvedIdentity?.sub)

        guard resolvedIdentity?.sub != nil || resolvedName != nil || nickname != nil else { return nil }
        return MeUser(
            userId: resolvedIdentity?.sub,
            name: resolvedName,
            nickname: nickname,
            profession: nil,
            bio: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    static func identity(from response: DirectCognitoProfileResponse) -> MeIdentity? {
        let sub = normalizedValue(response.profile?.sub) ?? attribute("sub", in: response)
        let givenName = normalizedValue(response.profile?.givenName) ?? attribute("given_name", in: response)
        let familyName = normalizedValue(response.profile?.familyName) ?? attribute("family_name", in: response)
        let preferredUsername = normalizedDisplayName(
            response.profile?.preferredUsername ?? attribute("preferred_username", in: response),
            userId: sub
        )
        let nickname = normalizedDisplayName(attribute("nickname", in: response), userId: sub)
        let name = normalizedDisplayName(
            response.profile?.name ?? attribute("name", in: response),
            userId: sub
        ) ?? normalizedDisplayName(
            combinedName(givenName: givenName, familyName: familyName),
            userId: sub
        )
        let phoneNumber = normalizedValue(response.profile?.phone) ?? attribute("phone_number", in: response)
        let email = normalizedValue(response.profile?.email) ?? attribute("email", in: response)
        let cognitoUsername = normalizedDisplayName(
            attribute("cognito:username", in: response) ?? attribute("cognito_username", in: response),
            userId: sub
        )
        let emailVerified = boolValue(attribute("email_verified", in: response))
        let phoneNumberVerified = boolValue(attribute("phone_number_verified", in: response))

        guard sub != nil || email != nil || phoneNumber != nil || name != nil || preferredUsername != nil || nickname != nil else {
            return nil
        }

        return MeIdentity(
            sub: sub,
            phoneNumber: phoneNumber,
            email: email,
            cognitoUsername: cognitoUsername,
            preferredUsername: preferredUsername,
            nickname: nickname,
            name: name,
            givenName: givenName,
            familyName: familyName,
            emailVerified: emailVerified,
            phoneNumberVerified: phoneNumberVerified
        )
    }

    static func cache(_ response: DirectCognitoProfileResponse) {
        let resolvedUser = user(from: response)
        let resolvedIdentity = identity(from: response)
        let resolvedProfileURL =
            normalizedValue(attribute("custom:profile_url", in: response))
            ?? normalizedValue(attribute("profile_url", in: response))
            ?? normalizedValue(attribute("picture", in: response))

        if let sub = normalizedValue(resolvedIdentity?.sub) {
            UserDefaults.standard.set(sub, forKey: "userId")
        }
        if let email = normalizedValue(resolvedIdentity?.email) {
            UserDefaults.standard.set(email, forKey: "userEmail")
        }
        if let phone = normalizedValue(resolvedIdentity?.phoneNumber) {
            UserDefaults.standard.set(phone, forKey: "userPhone")
        }
        if let resolvedProfileURL {
            UserDefaults.standard.set(resolvedProfileURL, forKey: "userProfileUrl")
        }

        let resolvedName = normalizedDisplayName(resolvedUser?.name, userId: resolvedIdentity?.sub)
            ?? normalizedDisplayName(combinedName(givenName: resolvedIdentity?.givenName, familyName: resolvedIdentity?.familyName), userId: resolvedIdentity?.sub)
            ?? normalizedDisplayName(resolvedUser?.nickname, userId: resolvedIdentity?.sub)
            ?? normalizedDisplayName(resolvedIdentity?.nickname, userId: resolvedIdentity?.sub)
            ?? normalizedDisplayName(resolvedIdentity?.preferredUsername, userId: resolvedIdentity?.sub)
            ?? normalizedDisplayName(resolvedIdentity?.cognitoUsername, userId: resolvedIdentity?.sub)

        if let resolvedName {
            UserDefaults.standard.set(resolvedName, forKey: "userName")
        }
    }

    static func errorMessage(from data: Data?) -> String? {
        guard let data else { return nil }
        if let decoded = try? JSONDecoder().decode(DirectCognitoProfileResponse.self, from: data) {
            return normalizedValue(decoded.message)
        }
        return nil
    }

    static func cachedUser() -> MeUser? {
        let userId = normalizedValue(UserDefaults.standard.string(forKey: "userId"))
        let name = normalizedDisplayName(UserDefaults.standard.string(forKey: "userName"), userId: userId)

        guard userId != nil || name != nil else { return nil }
        return MeUser(
            userId: userId,
            name: name,
            nickname: nil,
            profession: nil,
            bio: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    static func cachedIdentity() -> MeIdentity? {
        let sub = normalizedValue(UserDefaults.standard.string(forKey: "userId"))
        let email = normalizedValue(UserDefaults.standard.string(forKey: "userEmail"))
        let phoneNumber = normalizedValue(UserDefaults.standard.string(forKey: "userPhone"))
        let name = normalizedDisplayName(UserDefaults.standard.string(forKey: "userName"), userId: sub)

        guard sub != nil || email != nil || phoneNumber != nil || name != nil else { return nil }
        return MeIdentity(
            sub: sub,
            phoneNumber: phoneNumber,
            email: email,
            cognitoUsername: nil,
            preferredUsername: nil,
            nickname: nil,
            name: name,
            givenName: nil,
            familyName: nil,
            emailVerified: nil,
            phoneNumberVerified: nil
        )
    }

    private static func attribute(_ key: String, in response: DirectCognitoProfileResponse) -> String? {
        normalizedValue(response.attributes?[key])
    }

    private static func combinedName(givenName: String?, familyName: String?) -> String? {
        let parts = [givenName, familyName]
            .compactMap { normalizedValue($0) }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    private static func normalizedDisplayName(_ value: String?, userId: String?) -> String? {
        guard let trimmed = normalizedValue(value) else { return nil }
        if trimmed.caseInsensitiveCompare("guest") == .orderedSame { return nil }
        if let userId, trimmed == userId { return nil }
        if looksLikeOpaqueIdentifier(trimmed) { return nil }
        return trimmed
    }

    private static func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolValue(_ value: String?) -> Bool? {
        guard let value = normalizedValue(value)?.lowercased() else { return nil }
        if value == "true" || value == "1" { return true }
        if value == "false" || value == "0" { return false }
        return nil
    }

    private static func hasRequiredScope(_ accessToken: String) -> Bool {
        guard
            let claims = decodeJWT(accessToken),
            let scopeString = normalizedValue(claims["scope"] as? String)
        else {
            return false
        }

        let scopes = scopeString.split(whereSeparator: \.isWhitespace).map(String.init)
        return scopes.contains(requiredScope)
    }

    private static func decodeJWT(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
        base64 = base64.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padLen = 4 - (base64.count % 4)
        if padLen < 4 {
            base64 += String(repeating: "=", count: padLen)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func looksLikeOpaqueIdentifier(_ value: String) -> Bool {
        let hyphenCount = value.filter { $0 == "-" }.count
        guard hyphenCount >= 3 else { return false }

        let compact = value.replacingOccurrences(of: "-", with: "")
        guard compact.count >= 16 else { return false }

        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return compact.unicodeScalars.allSatisfy { hexDigits.contains($0) }
    }
}

@MainActor
final class MeProfileViewModel: ObservableObject {
    @Published var user: MeUser?
    @Published var identity: MeIdentity?
    @Published var isLoading = false
    @Published var errorText: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        guard !hasLoaded else { return }
        hasLoaded = true
        await load()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            print("[Profile] request: GET \(AppEndpoints.Gateway.usersMe.absoluteString)")
            let profile = try await UsersProfileService.fetchMe()
            user = UsersProfileService.meUser(from: profile)
            identity = UsersProfileService.meIdentity(from: profile)
            print(
                "[Profile] users_me success userId=\(identity?.sub ?? user?.userId ?? "nil") " +
                "name=\(identity?.name ?? user?.name ?? "nil") " +
                "email=\(identity?.email ?? "nil")"
            )
            errorText = nil
            return
        } catch {
            print("[Profile] users_me fallback to Cognito profile: \(error.localizedDescription)")
        }

        do {
            print("[Profile] request: POST \(AppEndpoints.Lambda.cognitoProfile.absoluteString)")
            print("[Profile] body: accessToken=<redacted>")

            let decoded = try await CognitoDirectProfileService.fetchForCurrentUser()
            let resolvedUser = CognitoDirectProfileService.user(from: decoded)
            let resolvedIdentity = CognitoDirectProfileService.identity(from: decoded)

            guard resolvedUser != nil || resolvedIdentity != nil else {
                errorText = decoded.message ?? "Profile not found"
                return
            }

            user = resolvedUser
            identity = resolvedIdentity
        } catch CognitoProfileError.missingRequiredScope {
            user = CognitoDirectProfileService.cachedUser()
            identity = CognitoDirectProfileService.cachedIdentity()
            errorText = nil
        } catch APIError.statusCode(let status, let data) {
            let message = CognitoDirectProfileService.errorMessage(from: data) ?? "Server \(status)"
            if OIDCAuthManager.shared.handleExpiredSessionIfNeeded(message: message) {
                errorText = nil
            } else {
                errorText = message
            }
        } catch {
            if OIDCAuthManager.shared.handleExpiredSessionIfNeeded(error: error) {
                errorText = nil
            } else {
                errorText = error.localizedDescription
            }
        }
    }
}
