//
//  SocketLogView.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/10/25.
//  websocketconnection
//

import SwiftUI

struct SocketLogView: View {
    @EnvironmentObject var socket: AWSWebSocketClient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WebSocket").font(.headline)
                Spacer()
                Circle()
                    .fill(socket.state.isConnected ? .green : (socket.state == .connecting ? .orange : .gray))
                    .frame(width: 10, height: 10)
                Text(socket.state.shortText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let ms = socket.lastPingMs {
                Text("Last Ping: \(ms) ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
            ScrollView {
                Text(socket.lastEvent)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Socket Logs")
        .navigationBarTitleDisplayMode(.inline)
    }
}


