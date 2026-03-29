//
//  ShareSheet.swift
//  Critic
//
//  Created by chinni Rayapudi on 10/9/25.
//

import Foundation
import SwiftUI
import UIKit

struct ShareSheet2: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
