//
//  AppDelegate.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/11/25.
//

import SwiftUI
import AppAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if let flow = OIDCAuthManager.shared.currentAuthorizationFlow,
           flow.resumeExternalUserAgentFlow(with: url) {
            OIDCAuthManager.shared.currentAuthorizationFlow = nil
            return true
        }
        return false
    }
}
