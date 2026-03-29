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
    let avatarUrl: String?
    let lat: Double
    let lon: Double
    let distanceM: Double?
    let isSimulated: Bool?
}

private struct NearbyEnvelope: Decodable {
    // Lambda sends one of:
    //  - { "type":"nearbyUsers", "center":{...}, "count":N, "users":[...] }
    //  - { "type":"updateLocationAck", "you":{...}, "nearbyCount":N, "nearby":[...] }
    let type: String?
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
    func connect() {
        guard task == nil || state == .disconnected || isTerminal(state) else {
            log("connect(): ignored; state=\(state.shortText)")
            return
        }
        reconnectEnabled = true
        var req = URLRequest(url: config.url)
        config.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        state = .connecting
        log("WS → connecting \(config.url.absoluteString)")

        task = session.webSocketTask(with: req)
        task?.resume()
        startReceiveLoop()
    }

    func disconnect() {
        reconnectEnabled = false
        reconnectWorkItem?.cancel(); reconnectWorkItem = nil
        stopPingTimer()
        receiveLoopActive = false
        state = .closing
        let currentTask = task
        task = nil
        currentTask?.cancel(with: .normalClosure, reason: "Client closing".data(using: .utf8))
        state = .disconnected
        log("WS → disconnected")
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
    func sendUpdateLocation(userId: String, latitude: Double, longitude: Double) {
        let payload: [String: Any] = [
            "action": "updateLocation",
            "userId": userId,
            "latitude": latitude,
            "longitude": longitude
        ]
        send(json: payload)
    }

    func sendGetNearbyUsers(userId: String, latitude: Double, longitude: Double, radiusMeters: Double) {
        let payload: [String: Any] = [
            "action": "getNearbyUsers",
            "userId": userId,
            "latitude": latitude,
            "longitude": longitude,
            "radiusMeters": radiusMeters
        ]
        send(json: payload)
    }

    // MARK: - Private
    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else {
            log("send(json:) encoding error")
            return
        }
        send(text: text)
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
            if !arr.isEmpty {
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
        DispatchQueue.main.async { self.state = .failed(msg) }
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
        DispatchQueue.main.async { self.state = .closed(code: closeCode, reason: reasonStr) }
        stopPingTimer()
        log("Closed code=\(closeCode.rawValue) reason=\(reasonStr ?? "nil")")
        scheduleReconnectIfNeeded()
    }
}
