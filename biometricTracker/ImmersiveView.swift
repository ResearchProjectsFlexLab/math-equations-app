//
//  ImmersiveView.swift
//  biometricTracker
//
//  Created by Prisha Marpu on 4/9/26.
//

import SwiftUI
import RealityKit

/// Surroundings for the session. During the 1-minute rests the participant sits in a
/// calm, snowy mountain range (see MountainScene). During the test it switches to a
/// distraction-free "test room": a dark dome, a softly lit floor and a faint horizon
/// ring, so the participant only sees the questions.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    private var isResting: Bool {
        let phase = appModel.mathManager.phase
        return phase == .relaxBefore || phase == .relaxAfter
    }

    var body: some View {
        RealityView { content in
            let room = Self.makeTestRoom()
            room.name = Self.testRoomName
            content.add(room)

            let mountains = await MountainScene.make()
            mountains.isEnabled = false
            content.add(mountains)
        } update: { content in
            // Snowy mountains for the rest minutes; the plain, dark room for the test itself.
            let resting = isResting
            content.entities.first { $0.name == MountainScene.entityName }?.isEnabled = resting
            content.entities.first { $0.name == Self.testRoomName }?.isEnabled = !resting
        }
    }

    private static let testRoomName = "TestRoom"

    private static func makeTestRoom() -> Entity {
        let root = Entity()

        // Dome: a large sphere flipped inside-out so we see its inner surface.
        let dome = ModelEntity(
            mesh: .generateSphere(radius: 40),
            materials: [UnlitMaterial(color: UIColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1))]
        )
        dome.scale = SIMD3<Float>(-1, 1, 1)
        root.addChild(dome)

        // Floor: a slightly lighter disc so the room has a sense of ground.
        let floor = ModelEntity(
            mesh: .generateCylinder(height: 0.01, radius: 12),
            materials: [UnlitMaterial(color: UIColor(red: 0.09, green: 0.11, blue: 0.19, alpha: 1))]
        )
        floor.position = [0, -0.005, 0]
        root.addChild(floor)

        // A soft spotlight pool under the participant.
        let pool = ModelEntity(
            mesh: .generateCylinder(height: 0.012, radius: 1.6),
            materials: [UnlitMaterial(color: UIColor(red: 0.16, green: 0.20, blue: 0.32, alpha: 1))]
        )
        root.addChild(pool)

        // Faint horizon ring of small lights, for orientation without distraction.
        let dotMaterial = UnlitMaterial(color: UIColor(red: 0.35, green: 0.45, blue: 0.75, alpha: 1))
        let dotMesh = MeshResource.generateSphere(radius: 0.06)
        let count = 48
        for i in 0..<count {
            let angle = Float(i) / Float(count) * 2 * .pi
            let dot = ModelEntity(mesh: dotMesh, materials: [dotMaterial])
            dot.position = [cos(angle) * 14, 1.4, sin(angle) * 14]
            root.addChild(dot)
        }

        return root
    }
}
