//
//  ARNearbyView.swift
//  Critic
//
//  iOS 15+ compatible AR overlay that shows nearby users as 3D billboards.
//  - No TextureResource/CGImage usage
//  - No BillboardComponent
//  - No Transform(lookingAt:) overloads
//

import SwiftUI
import RealityKit
import ARKit
import CoreLocation
import Combine
import UIKit

// MARK: - Public SwiftUI wrapper

struct ARNearbyView: View {
    let centerUser: UserLocation
    let users: [UserLocation]

    var body: some View {
        ARViewContainer(centerUser: centerUser, users: users)
            .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - UIViewRepresentable

private struct ARViewContainer: UIViewRepresentable {
    let centerUser: UserLocation
    let users: [UserLocation]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.worldAlignment = .gravity
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        if #available(iOS 15.0, *) {
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        }
        arView.environment.lighting.intensityExponent = 1.0

        context.coordinator.install(on: arView)
        context.coordinator.sync(centerUser: centerUser, users: users)

        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.sync(centerUser: centerUser, users: users)
    }

    // MARK: - Coordinator

    final class Coordinator {
        private weak var arView: ARView?
        private var userAnchors: [String: AnchorEntity] = [:]  // userId -> anchor
        private var updateCancellable: Cancellable?

        func install(on arView: ARView) {
            self.arView = arView
            // Per-frame callback: rotate each marker to face camera (yaw only)
            updateCancellable = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                self?.faceCameraYawOnly()
            }
        }

        func sync(centerUser: UserLocation, users: [UserLocation]) {
            guard let arView = arView else { return }

            // Remove anchors that are no longer present
            let incoming = Set(users.map { $0.id })
            for (id, anchor) in userAnchors where !incoming.contains(id) {
                anchor.removeFromParent()
                userAnchors.removeValue(forKey: id)
            }

            let center = CLLocationCoordinate2D(latitude: centerUser.latitude,
                                                longitude: centerUser.longitude)

            for u in users {
                let id = u.id
                let pos = enuPosition(center: center, user: u) // world position

                if let anchor = userAnchors[id] {
                    anchor.position = pos
                    if let root = anchor.children.first {
                        updateText(on: root, center: center, user: u)
                    }
                } else {
                    let anchor = AnchorEntity(world: pos)
                    let marker = makeMarker(center: center, user: u)
                    anchor.addChild(marker)
                    arView.scene.addAnchor(anchor)
                    userAnchors[id] = anchor
                }
            }
        }

        // MARK: - Face camera (yaw only)

        private func faceCameraYawOnly() {
            guard let arView = arView else { return }
            let camPos = arView.cameraTransform.translation

            for anchor in userAnchors.values {
                guard let root = anchor.children.first else { continue }

                // World-space position of marker
                let worldPos = root.position(relativeTo: nil)
                let dir = camPos - worldPos           // vector toward camera
                // Yaw angle around Y to face camera
                let yaw = atan2(dir.x, -dir.z)        // RealityKit forward is -Z

                var t = root.transform
                t.rotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
                root.transform = t
            }
        }

        // MARK: - Build nodes

        private func enuPosition(center: CLLocationCoordinate2D, user: UserLocation) -> SIMD3<Float> {
            let offset = metersOffset(from: center,
                                      to: CLLocationCoordinate2D(latitude: user.latitude,
                                                                 longitude: user.longitude))
            let east  = Float(offset.x)   // +x
            let north = Float(offset.y)   // +north -> -z
            let yUp: Float = 0
            return SIMD3<Float>(east, yUp, -north)
        }

        private func makeMarker(center: CLLocationCoordinate2D, user: UserLocation) -> Entity {
            // Root entity
            let root = Entity()
            root.name = user.id

            // Avatar sphere (simple, reliable material initializer)
            let radius: Float = 0.18
            let sphereMat = SimpleMaterial(color: .systemBlue, isMetallic: false)
            let sphere = ModelEntity(mesh: .generateSphere(radius: radius), materials: [sphereMat])

            // Label (name + distance)
            let label = makeText(center: center, user: user)
            label.position = SIMD3<Float>(0, -(radius + 0.06), 0)

            root.addChild(sphere)
            root.addChild(label)
            root.scale = SIMD3<Float>(repeating: 0.8)
            return root
        }

        private func updateText(on root: Entity,
                                center: CLLocationCoordinate2D,
                                user: UserLocation) {
            // Remove old text if present (we add as child index 1)
            if root.children.count >= 2 {
                root.children[1].removeFromParent()
            }
            let label = makeText(center: center, user: user)
            let radius: Float = 0.18
            label.position = SIMD3<Float>(0, -(radius + 0.06), 0)
            root.addChild(label)
        }

        private func makeText(center: CLLocationCoordinate2D, user: UserLocation) -> ModelEntity {
            let meters = distanceMeters(center: center,
                                        target: CLLocationCoordinate2D(latitude: user.latitude,
                                                                       longitude: user.longitude))
            let label = "\(user.displayName ?? user.id) · \(formatMeters(meters)) away"

            let mesh = MeshResource.generateText(
                label,
                extrusionDepth: 0.005,
                font: UIFont.systemFont(ofSize: 0.16, weight: .semibold),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )

            let mat = SimpleMaterial(color: .label, isMetallic: false)
            let model = ModelEntity(mesh: mesh, materials: [mat])
            model.scale = SIMD3<Float>(repeating: 0.35)
            return model
        }
    }
}

// MARK: - Math helpers

/// Planar meters offset (east, north) from `center` to `target`.
private func metersOffset(from center: CLLocationCoordinate2D,
                          to target: CLLocationCoordinate2D) -> SIMD2<Double> {
    let latRad = center.latitude * .pi / 180.0
    let metersPerDegLat = 111_000.0
    let metersPerDegLon = 111_320.0 * cos(latRad)
    let dx = (target.longitude - center.longitude) * metersPerDegLon // east
    let dy = (target.latitude  - center.latitude)  * metersPerDegLat // north
    return SIMD2<Double>(dx, dy)
}

private func distanceMeters(center: CLLocationCoordinate2D,
                            target: CLLocationCoordinate2D) -> Double {
    let off = metersOffset(from: center, to: target)
    return hypot(off.x, off.y)
}

private func formatMeters(_ meters: Double) -> String {
    if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
    return String(format: "%.0f m", meters)
}

