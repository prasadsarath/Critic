//
//  AppDelegate.swift
//  Critic
//
//  Created by chinni Rayapudi on 9/11/25.
//

import SwiftUI
import AppAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CrashReporting.configureIfAvailable()
        return true
    }

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
