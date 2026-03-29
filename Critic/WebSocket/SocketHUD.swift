//
//  SocketHUD.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/10/25.
//  websocketconnection
//

import SwiftUI

private struct HUDBanner: ViewModifier {
    @Binding var text: String?
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let t = text {
                    Text(t)
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: text)
    }
}

extension View {
    func hudBanner(text: Binding<String?>) -> some View {
        modifier(HUDBanner(text: text))
    }
}


