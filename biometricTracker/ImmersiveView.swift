//
//  ImmersiveView.swift
//  biometricTracker
//
//  Created by Prisha Marpu on 4/9/26.
//

import SwiftUI
import RealityKit

/// The whole session after Start: the participant sits in a quiet alpine valley (AlpineScene)
/// for the instructions and both rests, and the scene crossfades to a plain, dark "test room"
/// for the math test. Panels float in front of them; during the rests only faint text shows.
/// Pressing the Digital Crown ends the session early; what was recorded is still saved.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var stage = SceneStage()

    private var game: MathProblemManager { appModel.mathManager }

    var body: some View {
        RealityView { content, attachments in
            content.add(stage.root)
            if let panel = attachments.entity(for: "panel") {
                panel.position = [0, 1.25, -1.5]
                stage.panel = panel
                stage.root.addChild(panel)
            }
            if let rest = attachments.entity(for: "rest") {
                rest.position = [0, 0.95, -2.6]
                stage.restHUD = rest
                stage.root.addChild(rest)
            }
            // Sync every rendered frame for smooth fades and the breathing light.
            stage.updates = content.subscribe(to: SceneEvents.Update.self) { _ in
                stage.sync(with: appModel.mathManager)
            }
        } attachments: {
            Attachment(id: "panel") {
                SessionPanel().environment(appModel)
            }
            Attachment(id: "rest") {
                RestHUD().environment(appModel)
            }
        }
        .persistentSystemOverlays(.hidden)
        .onAppear {
            appModel.immersiveSpaceState = .open
            if appModel.isOpeningSpace {
                appModel.isOpeningSpace = false
                game.begin()
                // Nothing should float between the participant and the scene.
                dismissWindow(id: AppModel.controlWindowID)
            } else if !game.isRunning {
                // Opened without a session (e.g. restored by the system): don't trap the participant.
                Task { await dismissImmersiveSpace() }
            }
        }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            if game.isRunning { game.stop() }      // Digital Crown: end early and save the log
            showControlWindow()
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .finished || phase == .ready {
                showControlWindow()
                Task { await dismissImmersiveSpace() }
            }
        }
    }

    /// openWindow makes a new window each call, so only open one if none is showing.
    private func showControlWindow() {
        guard !appModel.controlWindowIsOpen else { return }
        appModel.controlWindowIsOpen = true
        openWindow(id: AppModel.controlWindowID)
    }
}

@MainActor
final class SceneStage {
    let root = Entity()
    var updates: EventSubscription?
    var panel: Entity?
    var restHUD: Entity?

    private let alpine = AlpineScene()
    private let testRoom = ImmersiveView.makeTestRoom()
    private var lastSync: Date?

    init() {
        root.addChild(alpine.root)
        testRoom.components.set(OpacityComponent(opacity: 0))
        testRoom.isEnabled = false
        root.addChild(testRoom)
    }

    func sync(with game: MathProblemManager) {
        let now = Date()
        let dt = Float(min(0.1, now.timeIntervalSince(lastSync ?? now)))
        lastSync = now

        let phase = game.phase
        let testing = phase == .testIntro || phase == .countdown || phase == .running
        Self.fade(testRoom, toward: testing ? 1 : 0, dt: dt)
        Self.fade(alpine.root, toward: testing ? 0 : 1, dt: dt)
        if alpine.root.isEnabled {
            let resting = phase == .relaxBefore || phase == .relaxAfter
            alpine.update(breath: resting ? game.breath(at: now) : 0.35, now: now)
        }
        panel?.isEnabled = phase == .instructions || testing
        restHUD?.isEnabled = phase == .relaxBefore || phase == .relaxAfter
    }

    /// Fades an entity's opacity toward a target over about two-thirds of a second, hiding it at zero.
    private static func fade(_ entity: Entity, toward target: Float, dt: Float) {
        let current = entity.components[OpacityComponent.self]?.opacity ?? 1
        let step = dt * 1.5
        let next = current < target ? min(target, current + step) : max(target, current - step)
        entity.components.set(OpacityComponent(opacity: next))
        entity.isEnabled = next > 0.001
    }
}

extension ImmersiveView {
    static func makeTestRoom() -> Entity {
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
