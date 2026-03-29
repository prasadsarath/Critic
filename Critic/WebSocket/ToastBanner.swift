//
//  ToastBanner.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/10/25.
//  websocketconnection
//
//  Created by chinni Rayapudi on 9/5/25.
//

import Foundation
import SwiftUI

struct ToastBanner: Identifiable, Equatable {
    enum Kind { case success, info, error }
    let id = UUID()
    let kind: Kind
    let message: String
    let duration: TimeInterval

    static func success(_ msg: String, duration: TimeInterval = 1.5) -> ToastBanner {
        .init(kind: .success, message: msg, duration: duration)
    }
    static func info(_ msg: String, duration: TimeInterval = 1.5) -> ToastBanner {
        .init(kind: .info, message: msg, duration: duration)
    }
    static func error(_ msg: String, duration: TimeInterval = 2.0) -> ToastBanner {
        .init(kind: .error, message: msg, duration: duration)
    }
}

private struct ToastContainer: ViewModifier {
    @Binding var toast: ToastBanner?

    func body(content: Content) -> some View {
        ZStack {
            content
            if let toast = toast {
                VStack {
                    HStack {
                        Image(systemName: icon(for: toast.kind))
                        Text(toast.message).bold()
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(bg(for: toast.kind))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .shadow(radius: 4)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration) {
                        withAnimation { self.toast = nil }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toast)
    }

    private func bg(for kind: ToastBanner.Kind) -> Color {
        switch kind { case .success: return .green; case .info: return .blue; case .error: return .red }
    }
    private func icon(for kind: ToastBanner.Kind) -> String {
        switch kind { case .success: return "checkmark.circle.fill"; case .info: return "info.circle.fill"; case .error: return "xmark.octagon.fill" }
    }
}

extension View {
    /// Attach an auto-dismiss banner: `.toast($vm.toast)`
    func toast(_ toast: Binding<ToastBanner?>) -> some View {
        modifier(ToastContainer(toast: toast))
    }
}

