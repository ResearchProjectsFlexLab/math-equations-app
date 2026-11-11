//
//  BaselineViews.swift
//  biometricTracker
//
//  Screens for the baseline before the math test: instructions, and the calm,
//  guided 1-minute rest used before and after the test.
//

import SwiftUI

// MARK: - Welcome (baseline instructions)

struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 36) {
            VStack(spacing: 12) {
                Text("Welcome")
                    .font(.extraLargeTitle)
                Text("First, a quiet minute to settle in.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                StepRow(number: 1, text: "Relax among quiet, snowy mountains for 1 minute, breathing slowly.")
                StepRow(number: 2, text: "Math test: 3 minutes. Look at an answer and pinch your fingers to choose it.")
                StepRow(number: 3, text: "Relax again for 1 minute.")
            }
            .padding(28)
            .frame(maxWidth: 640)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button(action: onStart) {
                Label("Start Baseline", systemImage: "play.fill")
                    .font(.title.weight(.semibold))
                    .frame(minWidth: 320, minHeight: 80)
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

// MARK: - Rest (1 minute, before and after the test)

/// A calm, guided minute: a softly glowing orb to breathe with (in for 4 s, out for 6 s —
/// a longer out-breath helps the body settle), and gentle prompts that change slowly.
/// No big clock and no red badge, so nothing pulls attention or adds pressure.
struct RestView: View {
    let isAfterTest: Bool
    let remaining: TimeInterval

    private static let inhale: Double = 4
    private static let exhale: Double = 6
    private static let promptSeconds: Double = 12

    private static let promptsBefore = [
        "Look out at the quiet, snowy peaks.",
        "Breathe in the cool, clean mountain air.",
        "Let your shoulders soften and drop.",
        "Watch the snow drift slowly down.",
        "There is nothing you need to do right now.",
    ]
    private static let promptsAfter = [
        "You did well. Let the test go.",
        "Look out at the still, snowy mountains.",
        "Breathe in the cool, clean mountain air.",
        "Relax your hands and your face.",
        "Watch the snow drift slowly down.",
    ]

    @State private var breathingIn = false
    @State private var promptIndex = 0

    private var prompts: [String] { isAfterTest ? Self.promptsAfter : Self.promptsBefore }
    private var progress: Double {
        1 - max(0, min(1, remaining / MathProblemManager.restDuration))
    }

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                QuietLoggingDot()
                Spacer()
            }
            .padding(.trailing, 140)

            Text(isAfterTest ? "Well done. Now, rest." : "Take a quiet moment in the mountains")
                .font(.largeTitle.weight(.medium))
                .foregroundStyle(.primary.opacity(0.9))

            BreathingOrb(expanded: breathingIn)
                .frame(width: 380, height: 380)

            Text(breathingIn ? "Breathe in…" : "…and slowly out")
                .font(.title2.weight(.regular))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 1.2), value: breathingIn)

            Text(prompts[promptIndex % prompts.count])
                .font(.title3.italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .id(promptIndex)
                .transition(.opacity)
                .frame(height: 30)

            Spacer(minLength: 0)

            // A faint line that fills over the minute — no numbers to watch.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(.white.opacity(0.28))
                        .frame(width: geo.size.width * progress)
                        .animation(.linear(duration: 0.25), value: progress)
                }
            }
            .frame(width: 300, height: 4)
            .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds of rest left")
        }
        .background {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.30, blue: 0.50).opacity(0.30),
                                              Color(red: 0.35, green: 0.50, blue: 0.70).opacity(0.20)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(-20)
        }
        .task { await breathe() }
        .task { await cyclePrompts() }
    }

    private func breathe() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: Self.inhale)) { breathingIn = true }
            try? await Task.sleep(for: .seconds(Self.inhale))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: Self.exhale)) { breathingIn = false }
            try? await Task.sleep(for: .seconds(Self.exhale))
        }
    }

    private func cyclePrompts() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.promptSeconds))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 1.5)) { promptIndex += 1 }
        }
    }
}

/// Soft, layered glow that swells on the in-breath and settles on the out-breath.
private struct BreathingOrb: View {
    let expanded: Bool

    // Icy, snow-light colours to match the mountains.
    private let lavender = Color(red: 0.70, green: 0.78, blue: 0.98)
    private let seafoam  = Color(red: 0.62, green: 0.86, blue: 0.95)

    var body: some View {
        ZStack {
            // Outer halo
            Circle()
                .fill(RadialGradient(colors: [seafoam.opacity(0.35), .clear],
                                     center: .center, startRadius: 40, endRadius: 190))
                .scaleEffect(expanded ? 1.0 : 0.7)
                .blur(radius: 20)

            // Main orb
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.85), lavender.opacity(0.75), seafoam.opacity(0.55)],
                                     center: .init(x: 0.42, y: 0.38), startRadius: 4, endRadius: 150))
                .frame(width: 260, height: 260)
                .scaleEffect(expanded ? 1.0 : 0.55)
                .blur(radius: 2)
                .shadow(color: lavender.opacity(0.5), radius: 40)

            // Faint guide ring at full size
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 1.5)
                .frame(width: 260, height: 260)
        }
        .accessibilityHidden(true)
    }
}

/// A small, still grey dot so researchers can see logging is on without a pulsing red badge.
private struct QuietLoggingDot: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.white.opacity(0.4)).frame(width: 7, height: 7)
            Text("Logging").font(.caption).foregroundStyle(.tertiary)
        }
        .accessibilityLabel("Logging is on")
    }
}

// MARK: - Test instructions

struct TestIntroView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 36) {
            HStack {
                RecordingBadge()
                Spacer()
            }
            .padding(.trailing, 140)

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

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
