//
//  BaselineViews.swift
//  biometricTracker
//
//  Screens for the baseline before the math test: instructions, colour practice
//  (to learn look + pinch), and the calm 1-minute rest used before and after the test.
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
                Text("First, a short warm-up before the math test.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                StepRow(number: 1, text: "Practice: a colour appears. Look at its name and pinch your fingers to choose it.")
                StepRow(number: 2, text: "Relax: breathe slowly with the circle for 1 minute.")
                StepRow(number: 3, text: "Math test: 3 minutes.")
                StepRow(number: 4, text: "Relax again for 1 minute.")
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

// MARK: - Colour practice

struct PracticeView: View {
    @Environment(AppModel.self) private var appModel

    private var game: MathProblemManager { appModel.mathManager }
    private var trial: ColourTrial { game.practiceTrial }

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 14) {
                RecordingBadge()
                Text("Practice \(game.practiceNumber) of \(MathProblemManager.practiceTrialCount)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Spacer()
            }
            .padding(.trailing, 140) // leave room for the Stop control

            Text("Which colour is this?")
                .font(.largeTitle.weight(.semibold))

            Circle()
                .fill(trial.target.swiftUIColor)
                .frame(width: 200, height: 200)
                .shadow(color: trial.target.swiftUIColor.opacity(0.5), radius: 24)
                .id(game.practiceNumber)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(duration: 0.4), value: game.practiceNumber)

            feedback
                .frame(height: 36)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                      spacing: 18) {
                ForEach(Array(trial.options.enumerated()), id: \.offset) { i, option in
                    AnswerTile(label: option.name,
                               state: tileState(for: i),
                               locked: game.practiceLastCorrect != nil,
                               action: { game.submitPractice(optionIndex: i) })
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var feedback: some View {
        if let correct = game.practiceLastCorrect {
            Label(correct ? "Correct!" : "It was \(trial.target.name)",
                  systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(correct ? .green : .red)
        } else {
            Text("Look at an answer, then pinch to choose it")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func tileState(for index: Int) -> AnswerTile.State {
        guard let correct = game.practiceLastCorrect else { return .idle }
        if index == trial.correctIndex                     { return .correct }
        if index == game.practiceLastIndex && !correct     { return .wrong }
        return .dimmed
    }
}

extension PracticeColour {
    var swiftUIColor: Color {
        switch self {
        case .red:    return .red
        case .blue:   return .blue
        case .green:  return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .purple: return .purple
        }
    }
}

// MARK: - Rest (1 minute, before and after the test)

struct RestView: View {
    let isAfterTest: Bool
    let remaining: TimeInterval

    /// One breath: 4 s in, 4 s out.
    private static let halfBreath: Double = 4

    @State private var breathingIn = false

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                RecordingBadge()
                Spacer()
            }
            .padding(.trailing, 140)

            VStack(spacing: 10) {
                Text(isAfterTest ? "Well done. Now relax." : "Relax")
                    .font(.extraLargeTitle2)
                Text("Sit comfortably and breathe slowly with the circle.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Circle()
                    .fill(.teal.opacity(0.18))
                    .frame(width: 320, height: 320)
                Circle()
                    .fill(.teal.opacity(0.55))
                    .frame(width: 320, height: 320)
                    .scaleEffect(breathingIn ? 1.0 : 0.45)
                Text(breathingIn ? "Breathe in" : "Breathe out")
                    .font(.title.weight(.semibold))
                    .contentTransition(.opacity)
            }
            .frame(height: 340)

            let secs = Int(remaining.rounded(.up))
            Text(String(format: "%d:%02d", secs / 60, secs % 60))
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(secs) seconds left")

            Text(isAfterTest ? "Your results appear when the minute is over."
                             : "The math test instructions appear when the minute is over.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .task { await breathe() }
    }

    private func breathe() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: Self.halfBreath)) { breathingIn = true }
            try? await Task.sleep(for: .seconds(Self.halfBreath))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: Self.halfBreath)) { breathingIn = false }
            try? await Task.sleep(for: .seconds(Self.halfBreath))
        }
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
                Text("Warm-up done. You're ready.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                StepRow(number: 1, text: "Look at an answer and pinch to choose it, just like the practice.")
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
