//
//  BaselineViews.swift
//  biometricTracker
//
//  The start window, and the panels shown inside the lake scene: the baseline
//  instructions, the faint text during the rests, the test instructions and the test.
//

import SwiftUI

// MARK: - Start window

struct WelcomeView: View {
    let isOpening: Bool
    let onStart: () -> Void
    let inWindow: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(.teal)
                .symbolEffect(.pulse, isActive: isOpening)

            VStack(spacing: 8) {
                Text("Math Test")
                    .font(.extraLargeTitle2)
                Text("1 min rest  ·  \(Int(MathProblemManager.testDuration / 60)) min test  ·  1 min rest")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Relax by a moonlit lake, answer math questions, then relax again. The log saves itself.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            if isOpening {
                VStack(spacing: 14) {
                    ProgressView("Getting ready…")
                    Button("Run in this window instead", action: inWindow)
                        .buttonStyle(.borderless)
                        .font(.footnote)
                }
            } else {
                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 36)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Session panel

/// What floats in front of the participant for each step. Shows nothing during the rests
/// (the scene and the faint RestHUD do the work there).
struct SessionPanel: View {
    @Environment(AppModel.self) private var appModel
    /// True when running in the control window because the immersive scene couldn't open.
    var inWindow = false

    private var game: MathProblemManager { appModel.mathManager }

    var body: some View {
        Group {
            switch game.phase {
            case .instructions:
                InstructionsCard(inWindow: inWindow)
            case .relaxBefore, .relaxAfter:
                if inWindow { RestHUD() } else { Color.clear.frame(width: 1, height: 1) }
            case .testIntro:
                card { TestIntroView(onStart: { game.start() }) }
            case .countdown:
                card { CountdownView(value: game.countdownValue) }
            case .running:
                card { TestView() }
            default:
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: game.phase)
    }

    /// The test screens sit on a glass panel in the scene; in the window they fill it.
    @ViewBuilder private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if inWindow {
            content()
                .overlay(alignment: .topTrailing) { StopControl(onStop: { game.stop() }) }
        } else {
            content()
                .padding(32)
                .frame(width: 980, height: 800)
                .overlay(alignment: .topTrailing) { StopControl(onStop: { game.stop() }).padding(28) }
                .glassBackgroundEffect()
        }
    }
}

// MARK: - Baseline instructions

/// Shown in the lake scene before the baseline: what to do, and a button to begin.
struct InstructionsCard: View {
    @Environment(AppModel.self) private var appModel
    var inWindow = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Before we begin")
                .font(.largeTitle.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                Label("Sit comfortably with your back supported.", systemImage: "chair")
                Label("Rest your hands on your lap and keep still.", systemImage: "hand.raised")
                Label("Look at the moon's reflection on the water.", systemImage: "moon.stars")
                Label("Breathe gently as the moonlight glows and fades.", systemImage: "wind")
            }
            .font(.title3)
            Text("This lasts 1 minute. The math test instructions follow.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("To stop at any time, press the Digital Crown.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button {
                appModel.mathManager.startBaseline()
            } label: {
                Label("Start baseline", systemImage: "play.fill")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .buttonBorderShape(.capsule)
        }
        .padding(inWindow ? 0 : 36)
        .frame(width: inWindow ? nil : 760)
        .glassBackgroundEffect(displayMode: inWindow ? .never : .always)
    }
}

// MARK: - Rest

/// Gentle words for the first few breaths of each rest, then only a faint progress line.
struct RestHUD: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let game = appModel.mathManager
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = game.restElapsed(at: context.date)
            let showWords = elapsed < MathProblemManager.breathCycle * 3
            let inhaling = game.isInhaling(at: context.date)
            VStack(spacing: 16) {
                Text(game.phase == .relaxAfter ? "Well done — now relax and breathe" : "Relax and breathe")
                    .font(.title2)
                    .opacity(elapsed < 6 ? 0.85 : 0)
                Text(inhaling ? "Breathe in…" : "Breathe out…")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .opacity(showWords ? 0.8 : 0)
                ProgressView(value: game.restProgress(at: context.date))
                    .tint(.white)
                    .frame(width: 320)
                    .opacity(0.35)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6)
            .animation(.easeInOut(duration: 1.2), value: showWords)
            .animation(.easeInOut(duration: 0.8), value: inhaling)
        }
    }
}

// MARK: - Test instructions

struct TestIntroView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text("Math Test")
                    .font(.extraLargeTitle)
                Text("Whenever you're ready.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                StepRow(number: 1, text: "Look at an answer and pinch your fingers to choose it.")
                StepRow(number: 2, text: "You have \(Int(MathProblemManager.secondsPerQuestion)) seconds for each question.")
                StepRow(number: 3, text: "The test lasts \(Int(MathProblemManager.testDuration / 60)) minutes, then you relax for 1 minute.")
            }
            .padding(28)
            .frame(maxWidth: 640)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button(action: onStart) {
                Label("Start Test", systemImage: "play.fill")
                    .font(.title.weight(.semibold))
                    .frame(minWidth: 300, minHeight: 80)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.extraLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("\(number)")
                .font(.title3.bold())
                .frame(width: 40, height: 40)
                .background(.blue.opacity(0.25), in: Circle())
            Text(text)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
