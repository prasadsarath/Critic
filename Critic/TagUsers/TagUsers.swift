import Foundation

// MARK: - API Models (tolerant decoding)

public struct TaggedUser: Identifiable, Decodable, Equatable {
    public var id: String { taggedUserId }
    public let taggedUserId: String
    public let expiresAt: Int?
    public let taggedAt: String?

    enum CodingKeys: String, CodingKey {
        case taggedUserId, expiresAt, taggedAt
        case tagged_user_id, taggedUserID, expires_at
    }

    public init(taggedUserId: String, expiresAt: Int?, taggedAt: String?) {
        self.taggedUserId = taggedUserId
        self.expiresAt = expiresAt
        self.taggedAt = taggedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let v = try? c.decode(String.self, forKey: .taggedUserId) {
            taggedUserId = v
        } else if let v = try? c.decode(String.self, forKey: .tagged_user_id) {
            taggedUserId = v
        } else if let v = try? c.decode(String.self, forKey: .taggedUserID) {
            taggedUserId = v
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.taggedUserId,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing tagged user id")
            )
        }

        func decodeExpires(_ key: CodingKeys) -> Int? {
            if let n = try? c.decode(Int.self, forKey: key) { return n }
            if let s = try? c.decode(String.self, forKey: key), let n = Int(s) { return n }
            return nil
        }
        expiresAt = decodeExpires(.expiresAt) ?? decodeExpires(.expires_at)
        taggedAt = (try? c.decode(String.self, forKey: .taggedAt)) ?? nil
    }
}

public struct TagListResponseCanonical: Decodable {
    public let status: Bool?
    public let userId: String?
    public let count: Int?
    public let taggedUsers: [TaggedUser]?
    public let items: [TaggedUser]?

    public var users: [TaggedUser] {
        if let taggedUsers = taggedUsers { return taggedUsers }
        if let items = items { return items }
        return []
    }
}

public enum TagAction: String { case tag, untag }

// MARK: - Service

public final class TagService {
    // JWT-protected API Gateway route
    private let baseURL = AppEndpoints.Gateway.tagging

    public init() {}

    public func list(userId: String) async throws -> [TaggedUser] {
        let request = APIRequestDescriptor(
            url: baseURL,
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            authorization: .currentUser
        )

        print("[TagService] GET Tagged request url=\(baseURL.absoluteString)?userId=\(userId)")
        let (data, response) = try await APIRequestExecutor.shared.perform(request)

        print("[TagService] GET Tagged status=\(response.statusCode)")
        if !(200..<300).contains(response.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            print("[TagService] GET Tagged non-2xx body: \(text)")
            throw URLError(.badServerResponse)
        }
        if let json = String(data: data, encoding: .utf8) {
            print("[TagService] GET Tagged raw: \(json)")
        }

        let decoded = try JSONDecoder().decode(TagListResponseCanonical.self, from: data)
        print("[TagService] GET Tagged decoded count=\(decoded.users.count)")
        return decoded.users
    }

    @discardableResult
    public func act(_ action: TagAction, userId: String, taggedUserId: String) async throws -> Bool {
        let body: [String: Any] = [
            "action": action.rawValue,
            "userId": userId,
            "taggedUserId": taggedUserId
        ]

        print("[TagService] POST action request body=\(body)")
        let request = APIRequestDescriptor(
            url: baseURL,
            method: .POST,
            body: try APIRequestDescriptor.jsonBody(body),
            authorization: .currentUser
        )
        let (data, response) = try await APIRequestExecutor.shared.perform(request)

        print("[TagService] POST action status=\(response.statusCode)")
        if !(200..<300).contains(response.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            print("[TagService] POST action non-2xx body: \(text)")
            throw URLError(.badServerResponse)
        }

        let jsonStr = String(data: data, encoding: .utf8) ?? ""
        print("[TagService] POST action raw: \(jsonStr)")

        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = obj["status"] as? Bool {
            print("[TagService] POST parsed status=\(status)")
            return status
        }
        print("[TagService] POST no explicit status; assuming success")
        return true
    }
}

// MARK: - Tiny helper (used by Tagged tab)
public func timeRemainingString(until epoch: Int?) -> String? {
    guard let epoch = epoch else { return nil }
    let now = Date()
    let end = Date(timeIntervalSince1970: TimeInterval(epoch))
    let diff = Int(end.timeIntervalSince(now))
    guard diff > 0 else { return "expired" }
    let hrs = diff / 3600
    let mins = (diff % 3600) / 60
    if hrs > 0 { return "\(hrs)h \(mins)m left" }
    return "\(mins)m left"
}
