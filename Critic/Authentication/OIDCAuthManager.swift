//
//  OIDCAuthManager.swift
//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//

import Foundation
import AppAuth
import UIKit
import Security

enum SessionTerminationKind {
    case standardLogout
    case accountDeletion

    var resetsOnboarding: Bool {
        switch self {
        case .standardLogout:
            return false
        case .accountDeletion:
            return true
        }
    }
}

final class OIDCAuthManager: NSObject, ObservableObject {
    static let shared = OIDCAuthManager()
    private static let authStateAccount = "authState"
    private static let authStateService = Bundle.main.bundleIdentifier ?? "Critic.AuthState"

    private(set) var authState: OIDAuthState?
    var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private var isStartingAuthorization = false

    // MARK: - Your pool / Hosted UI details

    // NOTE: You switched to the “account ong” pool
    private let issuer = AppEndpoints.Auth.issuer
    private let clientID = AppEndpoints.Auth.clientID
    private let redirectURI = AppEndpoints.Auth.redirectURI
    private let logoutRedirectURI = AppEndpoints.Auth.logoutRedirectURI
    private let cognitoUserAdminScope = "aws.cognito.signin.user.admin"
    private let requestsAdminScopeAtLogin = false

    /// Treat “any saved state” as restorable; access token might be expired but the refresh token is still valid.
    var hasAuthState: Bool { authState != nil }

    /// Public read-only: is a Hosted UI flow currently presented?
    var isSigningIn: Bool { currentAuthorizationFlow != nil || isStartingAuthorization }

    override init() {
        super.init()
        loadAuthState()
    }

    // MARK: - Public helpers

    /// Current userId (Cognito `sub`) if known.
    func currentUserId() -> String? {
        UserDefaults.standard.string(forKey: "userId")
    }

    private func authorizationScopes(includePhone: Bool, includeAdminScope: Bool) -> [String] {
        var scopes = [OIDScopeOpenID, "email"]
        if includePhone {
            scopes.append("phone")
        }
        if includeAdminScope {
            scopes.append(cognitoUserAdminScope)
        }
        return scopes
    }

    private func isInvalidScopeError(_ error: Error?) -> Bool {
        let description = error?.localizedDescription.lowercased() ?? ""
        return description.contains("invalid_scope")
    }

    private func beginAuthorization(
        configuration: OIDServiceConfiguration,
        presentingViewController: UIViewController,
        prefersEphemeral: Bool,
        extraParams: [String: String]?,
        includePhoneScope: Bool,
        includeAdminScope: Bool
    ) {
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: clientID,
            scopes: authorizationScopes(includePhone: includePhoneScope, includeAdminScope: includeAdminScope),
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: extraParams
        )

        let callback: (OIDAuthState?, Error?) -> Void = { [weak self] state, error in
            guard let self else { return }
            self.isStartingAuthorization = false
            self.currentAuthorizationFlow = nil

            if state == nil, includeAdminScope, self.isInvalidScopeError(error) {
                print("[Auth] \(self.cognitoUserAdminScope) is not enabled on the app client. Skipping silent retry to avoid duplicate Hosted UI prompts.")
                NotificationCenter.default.post(name: .loginFailed, object: error)
                return
            }

            self.handleAuthCallback(authState: state, error: error)
        }

        if let agent = OIDExternalUserAgentIOS(
            presenting: presentingViewController,
            prefersEphemeralSession: prefersEphemeral
        ) {
            currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                externalUserAgent: agent,
                callback: callback
            )
        } else {
            currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: presentingViewController,
                callback: callback
            )
        }
        isStartingAuthorization = false
    }

    // MARK: - Sign In (Hosted UI)
    func signIn(presentingViewController: UIViewController) {
        guard !isSigningIn else { return }
        isStartingAuthorization = true

        let forceFreshLogin = UserDefaults.standard.bool(forKey: "justLoggedOut")
        print("[Auth] signIn invoked. forceFreshLogin=\(forceFreshLogin)")

        OIDAuthorizationService.discoverConfiguration(forIssuer: issuer) { configuration, error in
            guard let configuration else {
                self.isStartingAuthorization = false
                print("‼️ Discovery error: \(error?.localizedDescription ?? "unknown")")
                NotificationCenter.default.post(name: .loginFailed, object: error)
                return
            }

            var extraParams: [String: String]? = nil
            if forceFreshLogin {
                extraParams = ["prompt": "login", "max_age": "0"]
            }

            let prefersEphemeral = forceFreshLogin // avoid reusing prior SSO cookies after logout
            self.beginAuthorization(
                configuration: configuration,
                presentingViewController: presentingViewController,
                prefersEphemeral: prefersEphemeral,
                extraParams: extraParams,
                includePhoneScope: true,
                includeAdminScope: self.requestsAdminScopeAtLogin
            )
            if forceFreshLogin {
                UserDefaults.standard.set(false, forKey: "justLoggedOut")
            }
        }
    }

    // MARK: - Callback
    private func handleAuthCallback(authState: OIDAuthState?, error: Error?) {
        self.currentAuthorizationFlow = nil

        if let authState {
            print("✅ Sign-in completed. Persisting auth state…")
            self.authState = authState
            self.saveAuthState()

            // Any successful Hosted UI callback is a valid signed-in session.
            self.logAndCacheTokens(prefix: "[Login]")
            self.setAuthenticatedState(notify: true)

            // Fill any missing profile fields in the background without blocking navigation.
            self.fetchUserInfoAndCache()
        } else {
            print("‼️ Authorization error: \(error?.localizedDescription ?? "unknown")")
            NotificationCenter.default.post(name: .loginFailed, object: error)
        }
    }

    // MARK: - UserInfo (name/email/phone) → UserDefaults
    private func fetchUserInfoAndCache(onComplete: ((Bool) -> Void)? = nil) {
        func finish(_ result: Bool, syncReason: String? = "auth_profile_refresh") {
            if let syncReason, UserDefaults.standard.string(forKey: "userId") != nil {
                Task { await self.syncUsersBridgeIfPossible(reason: syncReason) }
            }
            onComplete?(result)
        }

        guard let authState else {
            print("[UserInfo] No auth state available.")
            finish(false, syncReason: nil)
            return
        }

        authState.performAction { accessToken, _, error in
            guard error == nil, let accessToken else {
                if self.handleExpiredSessionIfNeeded(error: error) {
                    finish(false, syncReason: nil)
                    return
                }
                print("[UserInfo] Could not fetch userinfo (token/action error). Marking logged-in anyway.")
                finish(false)
                return
            }

            Task {
                var verifiedFromUserInfo = false

                do {
                    _ = try await CognitoDirectProfileService.fetch(accessToken: accessToken)
                } catch CognitoProfileError.missingRequiredScope(let scope) {
                    print("[CognitoProfile] Direct profile fetch skipped because access token does not include \(scope).")
                } catch APIError.statusCode(let status, let data) {
                    let message = CognitoDirectProfileService.errorMessage(from: data) ?? "Server \(status)"
                    if self.handleExpiredSessionIfNeeded(message: message) {
                        finish(verifiedFromUserInfo, syncReason: nil)
                        return
                    }
                    print("‼️ [CognitoProfile] request error: \(message)")
                } catch {
                    if self.handleExpiredSessionIfNeeded(error: error) {
                        finish(verifiedFromUserInfo, syncReason: nil)
                        return
                    }
                    print("‼️ [CognitoProfile] request error: \(error.localizedDescription)")
                }

                guard
                    let config = self.authState?.lastAuthorizationResponse.request.configuration,
                    let userinfoEndpoint = config.discoveryDocument?.userinfoEndpoint
                else {
                    print("[UserInfo] No userinfo endpoint available; skipping OIDC userinfo fetch.")
                    finish(verifiedFromUserInfo)
                    return
                }

                do {
                    let request = APIRequestDescriptor(
                        url: userinfoEndpoint,
                        authorization: .bearer(accessToken)
                    )
                    let (data, response) = try await APIRequestExecutor.shared.perform(request)
                    print("[UserInfo] status=\(response.statusCode)")

                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let userId = (json["sub"] as? String) ?? UserDefaults.standard.string(forKey: "userId")
                        let email = json["email"] as? String
                        let phone = (json["phone_number"] as? String) ?? (json["phone"] as? String)
                        let profileURL = (json["picture"] as? String)
                            ?? (json["profile_url"] as? String)
                            ?? (json["custom:profile_url"] as? String)

                        let emailVerified = self.claimIsTrue(json["email_verified"])
                        let phoneVerified = self.claimIsTrue(json["phone_number_verified"])
                        verifiedFromUserInfo = emailVerified || phoneVerified

                        let rawName: String = (json["name"] as? String)
                            ?? [json["given_name"], json["family_name"]]
                                .compactMap { $0 as? String }
                                .joined(separator: " ")
                        let nickname = json["nickname"] as? String
                        let preferredUsername = json["preferred_username"] as? String
                        let resolvedName = rawName.isEmpty
                            ? (nickname ?? preferredUsername)
                            : rawName
                        let name = self.sanitizedCachedName(resolvedName, userId: userId)

                        if let email {
                            print("[UserInfo] email=\(email)")
                            UserDefaults.standard.set(email, forKey: "userEmail")
                        }
                        if let phone {
                            print("[UserInfo] phone=\(phone)")
                            UserDefaults.standard.set(phone, forKey: "userPhone")
                        }
                        if let profileURL {
                            print("[UserInfo] profile_url=\(profileURL)")
                            UserDefaults.standard.set(profileURL, forKey: "userProfileUrl")
                        }
                        if let name {
                            print("[UserInfo] name=\(name)")
                            UserDefaults.standard.set(name, forKey: "userName")
                        } else if self.shouldClearCachedName(UserDefaults.standard.string(forKey: "userName"), userId: userId) {
                            UserDefaults.standard.removeObject(forKey: "userName")
                        }
                    }
                } catch {
                    print("‼️ [UserInfo] request error: \(error.localizedDescription)")
                }
                finish(verifiedFromUserInfo)
            }
        }
    }

    // MARK: - Refresh (silent on relaunch)
    func refreshIfNeeded(completion: @escaping (Bool) -> Void) {
        guard let authState else { completion(false); return }
        authState.performAction { accessToken, _, error in
            if let accessToken {
                print("🔄 Refresh succeeded. accessToken(l=\(accessToken.count))")
                self.saveAuthState()
                self.logAndCacheTokens(prefix: "[Refresh]")
                self.setAuthenticatedState(notify: false)
                self.fetchUserInfoAndCache()
                completion(true)
            } else {
                if self.handleExpiredSessionIfNeeded(error: error) {
                    completion(false)
                    return
                }
                print("⚠️ Token refresh failed: \(error?.localizedDescription ?? "unknown")")
                completion(false)
            }
        }
    }

    // MARK: - Keychain Persistence
    func saveAuthState() {
        guard let state = authState else { return }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true) {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: Self.authStateAccount,
                kSecAttrService as String: Self.authStateService
            ]
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: Self.authStateAccount,
                kSecAttrService as String: Self.authStateService,
                kSecValueData as String: data
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            print("[AuthState] save deleteStatus=\(deleteStatus) addStatus=\(addStatus) bytes=\(data.count)")
        } else {
            print("[AuthState] save skipped: failed to archive auth state")
        }
    }

    func loadAuthState() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.authStateAccount,
            kSecAttrService as String: Self.authStateService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataRef: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &dataRef)
        if status == errSecItemNotFound {
            // Legacy fallback (older builds saved without kSecAttrService).
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: Self.authStateAccount,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            status = SecItemCopyMatching(legacyQuery as CFDictionary, &dataRef)
        }
        if status == errSecSuccess,
           let data = dataRef as? Data,
           let state = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) {
            self.authState = state
            print("[AuthState] load success bytes=\(data.count)")
            // Re-save to ensure the new service key is used.
            saveAuthState()
        } else if status == errSecSuccess {
            self.authState = nil
            print("[AuthState] load failed: found data but could not decode OIDAuthState")
        } else {
            self.authState = nil
            print("[AuthState] load missing status=\(status)")
        }
    }

    func clearAuthState() {
        authState = nil
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.authStateAccount,
            kSecAttrService as String: Self.authStateService
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.authStateAccount
        ]
        let legacyDeleteStatus = SecItemDelete(legacyQuery as CFDictionary)
        print("[AuthState] clear deleteStatus=\(deleteStatus) legacyDeleteStatus=\(legacyDeleteStatus)")
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "userPhone")
        UserDefaults.standard.removeObject(forKey: "userProfileUrl")
    }

    func completeLocalLogout(
        kind: SessionTerminationKind = .standardLogout,
        markJustLoggedOut: Bool = true
    ) {
        let defaults = UserDefaults.standard
        if markJustLoggedOut {
            defaults.set(true, forKey: "justLoggedOut")
        } else {
            defaults.removeObject(forKey: "justLoggedOut")
        }
        defaults.set(false, forKey: "isLoggedIn")
        if kind.resetsOnboarding {
            defaults.set(false, forKey: "hasCompletedOnboarding")
        }
        clearAuthState()
        NotificationCenter.default.post(name: .didLogout, object: nil)
    }

    // MARK: - Sign Out (Hosted UI)
    func signOut(kind: SessionTerminationKind = .standardLogout) {
        guard let config = authState?.lastAuthorizationResponse.request.configuration else {
            print("[Logout] No config; local clear only.")
            completeLocalLogout(kind: kind)
            return
        }

        // Open logout URL and clear locally (simple, avoids invalid request errors)
        var comps = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        comps.path = "/logout"
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "logout_uri", value: logoutRedirectURI.absoluteString),
            URLQueryItem(name: "redirect_uri", value: logoutRedirectURI.absoluteString)
        ]

        if let url = comps.url {
            print("[Logout] Opening fallback logout URL.")
            UIApplication.shared.open(url, options: [:]) { _ in
                self.completeLocalLogout(kind: kind)
            }
        } else {
            print("⚠️ Could not form logout URL. Clearing locally.")
            completeLocalLogout(kind: kind)
        }
    }
}

extension OIDCAuthManager {
    func sessionExpiredError() -> NSError {
        NSError(
            domain: "Auth",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Your session expired. Please sign in again."]
        )
    }

    func isSessionExpiredMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        return normalized.contains("invalid_grant")
            || normalized.contains("refresh token has expired")
            || normalized.contains("token expired")
            || normalized.contains("session expired")
    }

    @discardableResult
    func handleExpiredSessionIfNeeded(message: String?) -> Bool {
        guard isSessionExpiredMessage(message) else { return false }
        expireSession(reason: message ?? "Session expired")
        return true
    }

    @discardableResult
    func handleExpiredSessionIfNeeded(error: Error?) -> Bool {
        guard let error else { return false }

        let nsError = error as NSError
        let messages = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.userInfo[NSLocalizedDescriptionKey] as? String,
            nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
            nsError.userInfo["error"] as? String,
            nsError.userInfo["error_description"] as? String
        ]

        guard messages.contains(where: { isSessionExpiredMessage($0) }) else { return false }
        expireSession(reason: nsError.localizedDescription)
        return true
    }

    private func expireSession(reason: String) {
        print("[Auth] Session expired. reason=\(reason)")
        clearAuthState()

        DispatchQueue.main.async {
            UserDefaults.standard.set(true, forKey: "justLoggedOut")
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            NotificationCenter.default.post(name: .verificationNeeded, object: nil)
        }
    }
}

// MARK: - Tokens / Claims logging & caching
private extension OIDCAuthManager {
    func claimIsTrue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let s = value as? String { return s.lowercased() == "true" || s == "1" }
        if let n = value as? NSNumber { return n.intValue != 0 }
        return false
    }

    func sanitizedCachedName(_ value: String?, userId: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("guest") == .orderedSame { return nil }
        if let userId, trimmed == userId { return nil }
        if looksLikeOpaqueIdentifier(trimmed) { return nil }

        return trimmed
    }

    func shouldClearCachedName(_ value: String?, userId: String?) -> Bool {
        guard value != nil else { return false }
        return sanitizedCachedName(value, userId: userId) == nil
    }

    func looksLikeOpaqueIdentifier(_ value: String) -> Bool {
        let hyphenCount = value.filter { $0 == "-" }.count
        guard hyphenCount >= 3 else { return false }

        let compact = value.replacingOccurrences(of: "-", with: "")
        guard compact.count >= 16 else { return false }

        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return compact.unicodeScalars.allSatisfy { hexDigits.contains($0) }
    }

    func isVerified(claims: [String: Any]) -> Bool {
        claimIsTrue(claims["phone_number_verified"]) || claimIsTrue(claims["email_verified"])
    }

    func setAuthenticatedState(notify: Bool) {
        DispatchQueue.main.async {
            let current = UserDefaults.standard.bool(forKey: "isLoggedIn")
            UserDefaults.standard.set(true, forKey: "isLoggedIn")
            guard notify else { return }
            if !current {
                NotificationCenter.default.post(name: .didLogin, object: nil)
            }
        }
    }

    func decodeJWT(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
        base64 = base64.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")
        let padLen = 4 - (base64.count % 4)
        if padLen < 4 { base64 += String(repeating: "=", count: padLen) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    @discardableResult
    func logAndCacheTokens(prefix: String) -> Bool {
        let refreshToken = authState?.lastTokenResponse?.refreshToken
        let exp = authState?.lastTokenResponse?.accessTokenExpirationDate
        let accessToken = authState?.lastTokenResponse?.accessToken
        let idToken = authState?.lastTokenResponse?.idToken

        print("""
        \(prefix) Tokens:
          accessToken length=\(accessToken?.count ?? 0)
          idToken     length=\(idToken?.count ?? 0)
          refreshToken length=\(refreshToken?.count ?? 0)
          accessTokenExp=\(exp?.description ?? "nil")
        """)

        var verified = false
        if let idToken, let claims = decodeJWT(idToken) {
            let sub  = claims["sub"] as? String
            let email = claims["email"] as? String
            let phone = (claims["phone_number"] as? String) ?? (claims["phone"] as? String)
            let name =
                (claims["name"] as? String) ??
                [claims["given_name"] as? String, claims["family_name"] as? String]
                    .compactMap { $0 }
                    .joined(separator: " ")
            let preferredUsername = claims["preferred_username"] as? String
            let cognitoUsername = claims["cognito:username"] as? String
            let profileURL = (claims["picture"] as? String)
                ?? (claims["profile_url"] as? String)
                ?? (claims["custom:profile_url"] as? String)

            verified = isVerified(claims: claims)

            let resolvedName = name.isEmpty
                ? (preferredUsername ?? cognitoUsername ?? email?.split(separator: "@").first.map(String.init))
                : name
            let cachedName = sanitizedCachedName(resolvedName, userId: sub)

            print("\(prefix) ID Token claims: sub=\(sub ?? "nil"), email=\(email ?? "nil"), phone=\(phone ?? "nil"), name=\(cachedName ?? "nil") verified=\(verified)")

            if let sub { UserDefaults.standard.set(sub, forKey: "userId") }
            if let email { UserDefaults.standard.set(email, forKey: "userEmail") }
            if let phone { UserDefaults.standard.set(phone, forKey: "userPhone") }
            if let profileURL { UserDefaults.standard.set(profileURL, forKey: "userProfileUrl") }
            if let cachedName {
                UserDefaults.standard.set(cachedName, forKey: "userName")
            } else if shouldClearCachedName(UserDefaults.standard.string(forKey: "userName"), userId: sub) {
                UserDefaults.standard.removeObject(forKey: "userName")
            }
        } else {
            print("\(prefix) ⚠️ Could not decode ID token claims.")
        }

        return verified
    }
}

extension OIDCAuthManager {
    @discardableResult
    func syncUsersBridgeIfPossible(
        reason: String,
        overrideName: String? = nil,
        overrideEmail: String? = nil,
        overridePhone: String? = nil,
        overrideProfileURL: String? = nil
    ) async -> Bool {
        let defaults = UserDefaults.standard
        let userId = normalizedBridgeValue(defaults.string(forKey: "userId"))
        guard let userId else {
            print("[UsersBridge] skipped (\(reason)): missing userId")
            return false
        }

        let claims = currentIdentityClaims()
        let claimGivenName = normalizedBridgeValue(claims?["given_name"] as? String)
        let claimFamilyName = normalizedBridgeValue(claims?["family_name"] as? String)
        let combinedClaimName = [claimGivenName, claimFamilyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedName = sanitizedCachedName(
            overrideName
                ?? defaults.string(forKey: "userName")
                ?? (claims?["name"] as? String)
                ?? (combinedClaimName.isEmpty ? nil : combinedClaimName)
                ?? (claims?["preferred_username"] as? String)
                ?? (claims?["nickname"] as? String),
            userId: userId
        )

        let resolvedEmail = normalizedBridgeValue(
            overrideEmail
                ?? defaults.string(forKey: "userEmail")
                ?? (claims?["email"] as? String)
        )
        let resolvedPhone = normalizedBridgeValue(
            overridePhone
                ?? defaults.string(forKey: "userPhone")
                ?? (claims?["phone_number"] as? String)
                ?? (claims?["phone"] as? String)
        )
        let resolvedProfileURL = normalizedBridgeValue(
            overrideProfileURL
                ?? defaults.string(forKey: "userProfileUrl")
                ?? (claims?["picture"] as? String)
                ?? (claims?["profile_url"] as? String)
                ?? (claims?["custom:profile_url"] as? String)
        )
        let preferredUsername = sanitizedCachedName(
            claims?["preferred_username"] as? String,
            userId: userId
        )
        let nickname = sanitizedCachedName(
            claims?["nickname"] as? String,
            userId: userId
        )
        let cognitoUsername = sanitizedCachedName(
            claims?["cognito:username"] as? String,
            userId: userId
        )

        var payload: [String: Any] = [
            "reason": reason,
            "userId": userId,
            "source": "ios"
        ]
        if let resolvedName { payload["name"] = resolvedName }
        if let preferredUsername { payload["preferred_username"] = preferredUsername }
        if let nickname { payload["nickname"] = nickname }
        if let cognitoUsername { payload["cognito_username"] = cognitoUsername }
        if let claimGivenName { payload["given_name"] = claimGivenName }
        if let claimFamilyName { payload["family_name"] = claimFamilyName }
        if let resolvedEmail { payload["email"] = resolvedEmail }
        if let resolvedPhone { payload["phone"] = resolvedPhone }
        if let resolvedProfileURL { payload["profile_url"] = resolvedProfileURL }

        if let claims {
            if let value = claims["email_verified"] { payload["email_verified"] = claimIsTrue(value) }
            if let value = claims["phone_number_verified"] { payload["phone_number_verified"] = claimIsTrue(value) }
        }

        do {
            let request = APIRequestDescriptor(
                url: AppEndpoints.Gateway.usersBridge,
                method: .POST,
                headers: ["X-Critic-Client": "ios"],
                body: try APIRequestDescriptor.jsonBody(payload),
                authorization: .currentUser
            )

            print("[UsersBridge] request: POST \(AppEndpoints.Gateway.usersBridge.absoluteString) reason=\(reason)")
            let (data, response) = try await APIRequestExecutor.shared.perform(request)
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[UsersBridge] status=\(response.statusCode)")
            print("[UsersBridge] body=\(bodyText)")

            guard (200...299).contains(response.statusCode) else {
                return false
            }
            return true
        } catch {
            if handleExpiredSessionIfNeeded(error: error) {
                return false
            }
            print("[UsersBridge] request error: \(error.localizedDescription)")
            return false
        }
    }

    private func currentIdentityClaims() -> [String: Any]? {
        if let token = authState?.lastTokenResponse?.idToken, let claims = decodeJWT(token) {
            return claims
        }
        if let token = authState?.lastAuthorizationResponse.idToken, let claims = decodeJWT(token) {
            return claims
        }
        return nil
    }

    private func normalizedBridgeValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

// MARK: - Access token helper (shared)
extension OIDCAuthManager {
    /// Returns a fresh ID token, reloading saved state if needed. Throws if not signed in.
    func getIDToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            if self.authState == nil { self.loadAuthState() }
            guard let authState = self.authState else {
                continuation.resume(throwing: NSError(domain: "Auth", code: 401,
                                                      userInfo: [NSLocalizedDescriptionKey: "Missing ID token"]))
                return
            }
            authState.performAction { _, idToken, error in
                if let token = idToken {
                    continuation.resume(returning: token)
                } else if let error {
                    if self.handleExpiredSessionIfNeeded(error: error) {
                        continuation.resume(throwing: self.sessionExpiredError())
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: NSError(domain: "Auth", code: 401,
                                                          userInfo: [NSLocalizedDescriptionKey: "Missing ID token"]))
                }
            }
        }
    }

    /// Returns a fresh access token, reloading saved state if needed. Throws if not signed in.
    func getAccessToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            if self.authState == nil { self.loadAuthState() }
            guard let authState = self.authState else {
                continuation.resume(throwing: NSError(domain: "Auth", code: 401,
                                                      userInfo: [NSLocalizedDescriptionKey: "Missing access token"]))
                return
            }
            authState.performAction { accessToken, _, error in
                if let token = accessToken {
                    continuation.resume(returning: token)
                } else if let error {
                    if self.handleExpiredSessionIfNeeded(error: error) {
                        continuation.resume(throwing: self.sessionExpiredError())
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: NSError(domain: "Auth", code: 401,
                                                          userInfo: [NSLocalizedDescriptionKey: "Missing access token"]))
                }
            }
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let didLogin = Notification.Name("didLogin")
    static let didLogout = Notification.Name("didLogout")
    static let loginFailed = Notification.Name("loginFailed")
    static let verificationNeeded = Notification.Name("verificationNeeded")
}   

// MARK: - Debug logging helpers
extension OIDCAuthManager {
    /// Prints a one-line snapshot of the current signed-in user & token state.
    func printUserSnapshot(tag: String = "Snapshot") {
        let ud = UserDefaults.standard
        let isLoggedIn = ud.bool(forKey: "isLoggedIn")
        let userId     = ud.string(forKey: "userId")   ?? "nil"
        let userName   = ud.string(forKey: "userName") ?? "nil"
        let userEmail  = ud.string(forKey: "userEmail") ?? "nil"
        let userPhone  = ud.string(forKey: "userPhone") ?? "nil"

        let exp = authState?.lastTokenResponse?.accessTokenExpirationDate
        let idTokenLen = authState?.lastTokenResponse?.idToken?.count ?? 0
        let accessLen  = authState?.lastTokenResponse?.accessToken?.count ?? 0

        print("""
        [User \(tag)] isLoggedIn=\(isLoggedIn) \
        userId=\(userId) name=\(userName) email=\(userEmail) phone=\(userPhone) \
        accessTokenLen=\(accessLen) idTokenLen=\(idTokenLen) \
        accessTokenExp=\(exp?.description ?? "nil")
        """)
    }
}

// MARK: - UIKit helpers
extension UIApplication {
    func firstKeyWindow() -> UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    func topViewController(base: UIViewController? = UIApplication.shared.firstKeyWindow()?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
