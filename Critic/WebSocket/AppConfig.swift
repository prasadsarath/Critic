//
//  AppConfig.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/10/25.
//

import Foundation

enum AppConfig {
    // Replace with your WebSocket endpoint (NO trailing slash is fine either way)
    // e.g. wss://xrry9op8xl.execute-api.us-east-1.amazonaws.com/production
    static let wsURL = AppEndpoints.Realtime.webSocket

    /// Optional headers for custom authorizers (API key / Cognito JWT / etc.)
    /// minor changes
    static var wsHeaders: [String: String] {
        let headers: [String: String] = [:]
        // Example (Cognito):
        // if let jwt = UserDefaults.standard.string(forKey: "id_token") {
        //     headers["Authorization"] = "Bearer \(jwt)"
        // }
        // headers["x-api-key"] = "<API_KEY>"
        return headers
    }

    /// Handy builder used by the app to create the socket
    static var socketConfig: WebSocketConfig {
        WebSocketConfig(
            url: wsURL,
            headers: wsHeaders,
            autoReconnect: true,
            pingInterval: 100,
            maxReconnectDelay: 30
        )
    }
}
