//
//  WebSocketConfig.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/10/25.
//  websocketconnection
//

import Foundation

struct WebSocketConfig {
    let url: URL
    var headers: [String: String] = [:]
    var autoReconnect: Bool = true
    var pingInterval: TimeInterval = 25
    var maxReconnectDelay: TimeInterval = 30
}

