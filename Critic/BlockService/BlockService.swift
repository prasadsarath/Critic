//
//  BlockService.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/30/25.
//

import Foundation

public struct BlockItem: Decodable {
    public let id: String?
    public let blockedById: String?
    public let blockedId: String?
    public let reason: String?
    public let timestamp: String?
}

public final class BlockService {
    // JWT-protected API Gateway route
    private let baseURL = AppEndpoints.Gateway.blocking

    public init() {}

    @discardableResult
    public func block(blockedById: String, blockedId: String, reason: String? = nil) async throws -> Bool {
        let payload: [String: Any] = [
            "action": "block",
            "userId": blockedById,
            "targetId": blockedId,
            "reason": (reason ?? "user_block")
        ]

        print("[BlockService] POST block body=\(payload)")
        let request = APIRequestDescriptor(
            url: baseURL,
            method: .POST,
            body: try APIRequestDescriptor.jsonBody(payload),
            authorization: .currentUser
        )
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        print("[BlockService] POST status=\(response.statusCode)")
        let txt = String(data: data, encoding: .utf8) ?? "<no body>"
        print("[BlockService] POST body=\(txt)")
        guard (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = obj["status"] as? Bool { return status }
        return true
    }

    public func list(blockedById: String) async throws -> [BlockItem] {
        let request = APIRequestDescriptor(
            url: baseURL,
            queryItems: [URLQueryItem(name: "userId", value: blockedById)],
            authorization: .currentUser
        )
        print("[BlockService] GET \(baseURL.absoluteString)?userId=\(blockedById)")
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        print("[BlockService] GET status=\(response.statusCode)")
        let txt = String(data: data, encoding: .utf8) ?? "<no body>"
        print("[BlockService] GET body=\(txt)")
        guard (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = outer["blocked"] as? [[String: Any]] {
            return arr.map { dict in
                BlockItem(
                    id: dict["id"] as? String,
                    blockedById: dict["blockedById"] as? String,
                    blockedId: dict["blockedId"] as? String,
                    reason: dict["reason"] as? String,
                    timestamp: dict["timestamp"] as? String
                )
            }
        }
        return []
    }

    @discardableResult
    public func unblock(blockedById: String, blockedId: String) async throws -> Bool {
        let payload: [String: Any] = [
            "action": "unblock",
            "userId": blockedById,
            "targetId": blockedId
        ]
        print("[BlockService] POST unblock body=\(payload)")
        let request = APIRequestDescriptor(
            url: baseURL,
            method: .POST,
            body: try APIRequestDescriptor.jsonBody(payload),
            authorization: .currentUser
        )
        let (data, response) = try await APIRequestExecutor.shared.perform(request)
        print("[BlockService] POST unblock status=\(response.statusCode)")
        let txt = String(data: data, encoding: .utf8) ?? "<no body>"
        print("[BlockService] POST unblock body=\(txt)")
        guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return true
    }
}
