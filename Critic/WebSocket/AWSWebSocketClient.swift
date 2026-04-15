//
//  AWSWebSocketClient.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/10/25.
//  websocketconnection
//

import Foundation
import Combine

// MARK: - Inbound models from Lambda

struct NearbyUser: Identifiable, Decodable, Equatable {
    var id: String { userId }
    let userId: String
    let name: String?
    let email: String?
    let phone: String?
    let avatarUrl: String?
    let lat: Double
    let lon: Double
    let distanceM: Double?
    let isSimulated: Bool?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case userId
        case userID
        case user_id
        case name
        case displayName
        case display_name
        case userName
        case username
        case aliasName
        case aliasname
        case fullName
        case full_name
        case preferredUsername
        case preferred_username
        case nickname
        case email
        case userEmail
        case phone
        case phoneNumber
        case phone_number
        case mobile
        case mobileNumber
        case mobile_number
        case avatarUrl
        case avatarURL
        case profileUrl
        case profile_url
        case photoUrl
        case photo_url
        case imageUrl
        case image_url
        case lat
        case latitude
        case lon
        case lng
        case longitude
        case distanceM
        case distance_m
        case distanceMeters
        case distance_meters
        case distance
        case isSimulated
        case is_simulated
        case updatedAt
        case updated_at
        case lastSeenAt
        case last_seen_at
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func firstString(_ keys: [CodingKeys]) -> String? {
            for key in keys {
                if let value = try? container.decodeIfPresent(String.self, forKey: key),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            return nil
        }

        func firstDouble(_ keys: [CodingKeys]) -> Double? {
            for key in keys {
                if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                    return value
                }
                if let stringValue = try? container.decodeIfPresent(String.self, forKey: key),
                   let value = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return value
                }
            }
            return nil
        }

        func firstBool(_ keys: [CodingKeys]) -> Bool? {
            for key in keys {
                if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
                    return value
                }
                if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
                    switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "true", "1": return true
                    case "false", "0": return false
                    default: break
                    }
                }
            }
            return nil
        }

        guard let resolvedUserId = firstString([.userId, .userID, .user_id]) else {
            throw DecodingError.keyNotFound(
                CodingKeys.userId,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing nearby user id")
            )
        }

        let resolvedName = firstString([.name, .displayName, .display_name, .userName, .username, .aliasName, .aliasname, .fullName, .full_name, .preferredUsername, .preferred_username, .nickname])
        let resolvedEmail = firstString([.email, .userEmail])
        let resolvedPhone = firstString([.phone, .phoneNumber, .phone_number, .mobile, .mobileNumber, .mobile_number])
        let resolvedAvatar = firstString([.avatarUrl, .avatarURL, .profileUrl, .profile_url, .photoUrl, .photo_url, .imageUrl, .image_url])

        guard let resolvedLat = firstDouble([.lat, .latitude]),
              let resolvedLon = firstDouble([.lon, .lng, .longitude]) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing nearby user coordinates")
            )
        }

        self.userId = resolvedUserId
        self.name = resolvedName
        self.email = resolvedEmail
        self.phone = resolvedPhone
        self.avatarUrl = resolvedAvatar
        self.lat = resolvedLat
        self.lon = resolvedLon
        self.distanceM = firstDouble([.distanceM, .distance_m, .distanceMeters, .distance_meters, .distance])
        self.isSimulated = firstBool([.isSimulated, .is_simulated])
        self.updatedAt = firstString([.updatedAt, .updated_at, .lastSeenAt, .last_seen_at, .timestamp])
    }
}

private struct NearbyEnvelope: Decodable {
    // Lambda sends one of:
    //  - { "type":"nearbyUsers", "center":{...}, "count":N, "users":[...] }
    //  - { "type":"updateLocationAck", "you":{...}, "nearbyCount":N, "nearby":[...] }
    let type: String?
    let action: String?
    let users: [NearbyUser]?
    let nearby: [NearbyUser]?
    // optional fields ignored here
}

/// Lightweight WebSocket client for AWS API Gateway (iOS 15+ safe)
final class AWSWebSocketClient: NSObject, ObservableObject {

    // MARK: - Connection State
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case closing
        case closed(code: URLSessionWebSocketTask.CloseCode, reason: String?)
        case failed(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var shortText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting:   return "Connecting"
            case .connected:    return "Connected"
            case .closing:      return "Closing"
            case .closed(let code, _): return "Closed (\(code.rawValue))"
            case .failed(let msg):     return "Failed: \(msg)"
            }
        }
    }

    // MARK: - Published
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var lastEvent: String = "—"
    @Published private(set) var lastPingMs: Int? = nil

    // NEW: the latest “nearby within radius” list parsed from server messages
    @Published private(set) var nearbyUsers: [NearbyUser] = []

    // MARK: - Internals
    private let config: WebSocketConfig
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()
    private var task: URLSessionWebSocketTask?
    private var receiveLoopActive = false
    private var pingTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt: Int = 0
    private var reconnectEnabled = true

    init(config: WebSocketConfig) {
        self.config = config
        super.init()
    }

    deinit { disconnect() }

    // MARK: - Public
    func connect(headers: [String: String] = [:]) {
        guard task == nil || state == .disconnected || isTerminal(state) else {
            log("connect(): ignored; state=\(state.shortText)")
            return
        }
        reconnectEnabled = true
        var req = URLRequest(url: config.url)
        let mergedHeaders = config.headers.merging(headers) { _, new in new }
        mergedHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        state = .connecting
        log("WS → connecting \(config.url.absoluteString)")

        task = session.webSocketTask(with: req)
        task?.resume()
        startReceiveLoop()
    }

    func disconnect() {
        disconnect(gracefulClearUserId: nil, completion: nil)
    }

    func disconnect(gracefulClearUserId userId: String?, completion: (() -> Void)? = nil) {
        reconnectEnabled = false
        reconnectWorkItem?.cancel(); reconnectWorkItem = nil
        stopPingTimer()

        let currentTask = task
        guard let currentTask else {
            receiveLoopActive = false
            DispatchQueue.main.async {
                self.nearbyUsers = []
                self.state = .disconnected
            }
            log("WS → disconnected")
            completion?()
            return
        }

        if let userId,
           state.isConnected,
           let clearText = encodedText(for: [
               "action": "clearLocation",
               "userId": userId
           ]) {
            currentTask.send(.string(clearText)) { [weak self] err in
                if let err {
                    self?.log("WS → clearLocation send failed: \(err.localizedDescription)")
                } else {
                    self?.log("WS → clearLocation sent for userId=\(userId)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.finishDisconnect(currentTask, completion: completion)
                }
            }
            return
        }

        finishDisconnect(currentTask, completion: completion)
    }

    func send(text: String) {
        guard let task else {
            log("send(): no task")
            return
        }
        task.send(.string(text)) { [weak self] err in
            if let err { self?.handleError("Send error: \(err.localizedDescription)") }
            else { self?.log("Sent: \(text)") }
        }
    }

    func ping() {
        guard let task else { return }
        let start = Date()
        task.sendPing { [weak self] err in
            if let err { self?.handleError("Ping error: \(err.localizedDescription)") }
            else {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                self?.lastPingMs = ms
                self?.log("Ping RTT: \(ms) ms")
            }
        }
    }

    // MARK: - Convenience payloads (match Lambda actions)
    /// Sends the user's current location to the nearby socket backend.
    ///
    /// The payload contains the existing websocket contract fields only, while optional identity
    /// fields are included when present so nearby users can be rendered without extra lookups.
    ///
    /// - Parameters:
    ///   - userId: The authenticated user identifier.
    ///   - latitude: The latitude being published to the socket backend.
    ///   - longitude: The longitude being published to the socket backend.
    ///   - displayName: The optional display name attached to the update.
    ///   - email: The optional email attached to the update.
    ///   - profileUrl: The optional profile image URL attached to the update.
    func sendUpdateLocation(
        userId: String,
        latitude: Double,
        longitude: Double,
        displayName: String? = nil,
        email: String? = nil,
        profileUrl: String? = nil
    ) {
        var payload: [String: Any] = [
            "action": "updateLocation",
            "userId": userId,
            "latitude": latitude,
            "longitude": longitude
        ]
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["name"] = displayName
        }
        if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["email"] = email
        }
        if let profileUrl, !profileUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["profile_url"] = profileUrl
        }
        if let payloadText = encodedText(for: payload) {
            print("[WS] Sending updateLocation payload: \(payloadText)")
        }
        send(json: payload)
    }

    /// Requests the current nearby-user list from the socket backend.
    ///
    /// This call reuses the same location payload shape as `sendUpdateLocation` and adds the
    /// search radius so the backend can resolve the current nearby set around the device.
    ///
    /// - Parameters:
    ///   - userId: The authenticated user identifier.
    ///   - latitude: The latitude used as the nearby search center.
    ///   - longitude: The longitude used as the nearby search center.
    ///   - radiusMeters: The nearby search radius in meters.
    ///   - displayName: The optional display name attached to the request.
    ///   - email: The optional email attached to the request.
    ///   - profileUrl: The optional profile image URL attached to the request.
    func sendGetNearbyUsers(
        userId: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double,
        displayName: String? = nil,
        email: String? = nil,
        profileUrl: String? = nil
    ) {
        var payload: [String: Any] = [
            "action": "getNearbyUsers",
            "userId": userId,
            "latitude": latitude,
            "longitude": longitude,
            "radiusMeters": radiusMeters
        ]
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["name"] = displayName
        }
        if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["email"] = email
        }
        if let profileUrl, !profileUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["profile_url"] = profileUrl
        }
        if let payloadText = encodedText(for: payload) {
            print("[WS] Sending getNearbyUsers payload: \(payloadText)")
        }
        send(json: payload)
    }

    // MARK: - Private
    /// Encodes and sends a websocket JSON payload.
    ///
    /// The dictionary is transformed into a UTF-8 JSON string before being forwarded to the lower
    /// level text-sending path used by the socket task.
    ///
    /// - Parameter json: The JSON payload dictionary to send.
    private func send(json: [String: Any]) {
        guard let text = encodedText(for: json) else {
            log("send(json:) encoding error")
            return
        }
        send(text: text)
    }

    /// Converts a payload dictionary into a JSON string.
    ///
    /// The returned string is used both for websocket transmission and for human-readable debug
    /// logging of the final payload leaving the app.
    ///
    /// - Parameter json: The dictionary payload to encode.
    /// - Returns: A UTF-8 JSON string representation of the payload, or `nil` if encoding fails.
    private func encodedText(for json: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private func startReceiveLoop() {
        guard !receiveLoopActive else { return }
        receiveLoopActive = true
        receiveNext()
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.handleError("Receive error: \(error.localizedDescription)")
            case .success(let msg):
                switch msg {
                case .string(let s):
                    self.log("Recv: \(s)")
                    self.handleInboundJSON(s)
                case .data(let d):
                    self.log("Recv \(d.count) bytes")
                    if let s = String(data: d, encoding: .utf8) {
                        self.handleInboundJSON(s)
                    }
                @unknown default:
                    self.log("Recv: unknown")
                }
                self.receiveNext()
            }
        }
    }

    private func handleInboundJSON(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if let env = try? JSONDecoder().decode(NearbyEnvelope.self, from: data) {
            let arr = env.users ?? env.nearby ?? []
            let isNearbyUsersPayload = env.type == "nearbyUsers" || env.action == "nearbyUsers"
            if isNearbyUsersPayload {
                if arr.isEmpty {
                    log("[Nearby] parsed 0 user(s)")
                } else {
                    let summaries = arr.map {
                        let raw = $0.name ?? $0.email ?? $0.phone ?? "nil"
                        return "\($0.userId):\(raw)"
                    }.joined(separator: ", ")
                    log("[Nearby] parsed \(arr.count) user(s): \(summaries)")
                }
                DispatchQueue.main.async { self.nearbyUsers = arr }
            } else if !arr.isEmpty {
                let summaries = arr.map {
                    let raw = $0.name ?? $0.email ?? $0.phone ?? "nil"
                    return "\($0.userId):\(raw)"
                }.joined(separator: ", ")
                log("[Nearby] parsed \(arr.count) user(s): \(summaries)")
                DispatchQueue.main.async { self.nearbyUsers = arr }
            }
        }
    }

    private func startPingTimer() {
        stopPingTimer()
        guard config.pingInterval > 0 else { return }
        pingTimer = Timer.scheduledTimer(withTimeInterval: config.pingInterval, repeats: true) { [weak self] _ in
            self?.ping()
        }
        RunLoop.main.add(pingTimer!, forMode: .common)
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func scheduleReconnectIfNeeded() {
        guard config.autoReconnect, reconnectEnabled else { return }
        reconnectWorkItem?.cancel()
        reconnectAttempt += 1
        let delay = min(config.maxReconnectDelay, pow(2.0, Double(reconnectAttempt)))
        log("Reconnect in \(Int(delay))s…")
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func resetReconnect() {
        reconnectAttempt = 0
        reconnectWorkItem?.cancel(); reconnectWorkItem = nil
    }

    private func isTerminal(_ state: ConnectionState) -> Bool {
        switch state { case .closed, .failed: return true; default: return false }
    }

    private func handleError(_ msg: String) {
        DispatchQueue.main.async {
            self.state = .failed(msg)
            self.nearbyUsers = []
        }
        stopPingTimer()
        receiveLoopActive = false
        task = nil
        log(msg)
        scheduleReconnectIfNeeded()
    }

    private func log(_ s: String) {
        DispatchQueue.main.async {
            self.lastEvent = s
            print("WS:", s)
        }
    }

    private func finishDisconnect(_ currentTask: URLSessionWebSocketTask, completion: (() -> Void)?) {
        receiveLoopActive = false
        DispatchQueue.main.async {
            self.state = .closing
            self.nearbyUsers = []
        }
        if task === currentTask {
            task = nil
        }
        currentTask.cancel(with: .normalClosure, reason: "Client closing".data(using: .utf8))
        DispatchQueue.main.async {
            self.state = .disconnected
        }
        log("WS → disconnected")
        completion?()
    }
}

// MARK: - URLSessionWebSocketDelegate
extension AWSWebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol `protocol`: String?) {
        DispatchQueue.main.async {
            self.state = .connected
            self.resetReconnect()
        }
        reconnectEnabled = true
        startPingTimer()
        log("Opened (protocol: \(`protocol` ?? "nil"))")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) }
        if task === webSocketTask {
            task = nil
        }
        DispatchQueue.main.async {
            self.state = .closed(code: closeCode, reason: reasonStr)
            self.nearbyUsers = []
        }
        stopPingTimer()
        log("Closed code=\(closeCode.rawValue) reason=\(reasonStr ?? "nil")")
        scheduleReconnectIfNeeded()
    }
}
