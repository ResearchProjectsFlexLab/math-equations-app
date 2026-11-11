//
//  ContentView.swift
//  biometricTracker
//
//  Created by Prisha Marpu on 4/9/26.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The small control window: a Start button, and the results at the end.
/// The rest of the session happens in the immersive mountain scene.
struct ContentView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var notice: String?

    private var game: MathProblemManager { appModel.mathManager }

    var body: some View {
        ZStack {
            switch game.phase {
            case .ready:
                WelcomeView(isOpening: appModel.isOpeningSpace,
                            onStart: { Task { await start() } },
                            inWindow: runInWindow)
                    .transition(.opacity)
            case .finished:
                ResultsView(onRestart: { game.reset() })
                    .transition(.opacity)
            default:
                // Only seen if the immersive scene couldn't open: run the session here instead.
                SessionPanel(inWindow: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: game.phase)
        .padding(32)
        .frame(minWidth: 700, minHeight: 520)
        .overlay(alignment: .bottom) {
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary).padding(.bottom, 10)
            }
        }
        .onAppear { appModel.controlWindowIsOpen = true }
        .onDisappear { appModel.controlWindowIsOpen = false }
    }

    /// Opens the mountain scene. The scene begins the session when it appears.
    private func start() async {
        notice = nil
        appModel.isOpeningSpace = true
        let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
        if result != .opened, appModel.isOpeningSpace {
            notice = "Couldn't open the immersive scene, so the session is running here instead."
            runInWindow()
        }
    }

    private func runInWindow() {
        appModel.isOpeningSpace = false
        game.begin()
    }
}

// MARK: - Countdown

struct CountdownView: View {
    let value: Int

    var body: some View {
        VStack(spacing: 20) {
            RecordingBadge()
            Text("Get ready…")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 180, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: value)
            Text("Your first question appears in a moment.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Test in progress

struct TestView: View {
    @Environment(AppModel.self) private var appModel

    private var game: MathProblemManager { appModel.mathManager }

    var body: some View {
        VStack(spacing: 22) {
            // Header: recording + question number + level
            HStack(spacing: 14) {
                RecordingBadge()
                Text("Question \(game.questionNumber)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(game.currentLevel.title)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(levelColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(levelColor)
                Spacer()
                TestClock(remaining: game.testTimeRemaining)
            }
            .padding(.trailing, 140) // leave room for the Stop control

            TimerBar(remaining: game.timeRemaining,
                     total: MathProblemManager.secondsPerQuestion,
                     paused: game.lastCorrect != nil)

            // Question card
            Text(game.current.question)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .padding(.vertical, 40)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .id(game.questionNumber)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
                .animation(.easeOut(duration: 0.3), value: game.questionNumber)

            FeedbackLine(result: game.lastCorrect,
                         timedOut: game.lastCorrect == false && game.lastAnsweredIndex == nil,
                         correctAnswer: game.current.correctAnswer)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                      spacing: 18) {
                ForEach(Array(game.current.answers.enumerated()), id: \.offset) { i, answer in
                    AnswerTile(label: answer,
                               state: tileState(for: i),
                               locked: game.lastCorrect != nil,
                               action: { game.submit(answerIndex: i) })
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 28) {
                MiniStat(label: "Correct", value: "\(game.correctCount)", color: .green)
                MiniStat(label: "Wrong",   value: "\(game.wrongCount)",   color: .red)
                MiniStat(label: "Score",   value: "\(game.score)",        color: .blue)
                MiniStat(label: "Streak",  value: "\(game.streak)",       color: .orange)
            }
            .padding(.vertical, 12).padding(.horizontal, 24)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var levelColor: Color {
        switch game.currentLevel {
        case .easy:   return .green
        case .medium: return .orange
        case .hard:   return .red
        }
    }

    private func tileState(for index: Int) -> AnswerTile.State {
        guard let result = game.lastCorrect else { return .idle }
        if index == game.current.correctIndex                  { return .correct }
        if index == game.lastAnsweredIndex && !result           { return .wrong }
        return .dimmed
    }
}

/// Time left in the whole test, e.g. "2:41 left". Turns orange in the last 30 seconds.
struct TestClock: View {
    let remaining: TimeInterval

    var body: some View {
        let secs = Int(remaining.rounded(.up))
        Label(String(format: "%d:%02d left", secs / 60, secs % 60), systemImage: "clock")
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(secs <= 30 ? .orange : .primary)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityLabel("\(secs / 60) minutes \(secs % 60) seconds left in the test")
    }
}

struct TimerBar: View {
    let remaining: Double
    let total: Double
    let paused: Bool

    private var fraction: Double { max(0, min(1, remaining / total)) }
    private var color: Color {
        fraction > 0.5 ? .green : (fraction > 0.25 ? .orange : .red)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .foregroundStyle(color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * fraction)
                        .animation(.linear(duration: 0.1), value: fraction)
                }
            }
            .frame(height: 12)
            Text("\(Int(remaining.rounded(.up)))s")
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 48, alignment: .trailing)
        }
        .opacity(paused ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds left")
    }
}

struct FeedbackLine: View {
    let result: Bool?
    let timedOut: Bool
    let correctAnswer: String

    var body: some View {
        ZStack {
            if let result {
                Label(text(result), systemImage: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(result ? .green : .red)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("Choose an answer").font(.title3).foregroundStyle(.secondary)
            }
        }
        .frame(height: 36)
        .animation(.spring(duration: 0.3), value: result)
    }

    private func text(_ result: Bool) -> String {
        if result { return "Correct!" }
        return timedOut ? "Time's up — answer was \(correctAnswer)" : "Not quite — answer was \(correctAnswer)"
    }
}

// MARK: - Results

struct ResultsView: View {
    @Environment(AppModel.self) private var appModel
    let onRestart: () -> Void

    private var game: MathProblemManager { appModel.mathManager }

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Text("Test Complete")
                    .font(.extraLargeTitle2)
                if game.completedAllQuestions {
                    Text("The \(Int(MathProblemManager.testDuration / 60))-minute test is over. Thank you!")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                ScoreTile(label: "Correct",  value: "\(game.correctCount)/\(game.totalAnswered)", color: .green)
                Divider().frame(height: 50)
                ScoreTile(label: "Accuracy", value: "\(Int((game.accuracy * 100).rounded()))%", color: .primary)
                Divider().frame(height: 50)
                ScoreTile(label: "Score",    value: "\(game.score)", color: .blue)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            saveBanner

            Button(action: onRestart) {
                Label("New Test", systemImage: "arrow.counterclockwise")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 220, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var saveBanner: some View {
        if let url = game.savedLogURL {
            VStack(spacing: 6) {
                Label("Log downloaded", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                Text("Files › On My Apple Vision Pro › biometricTracker")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
        } else if let error = game.saveError {
            Label("Couldn't save the log: \(error)", systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Shared pieces

struct StopControl: View {
    let onStop: () -> Void
    /// During the rest the button stays available but goes soft grey, so it doesn't draw the eye.
    var quiet: Bool = false

    var body: some View {
        Button(action: onStop) {
            Label("Stop", systemImage: "stop.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(quiet ? .secondary : .primary)
                .frame(minWidth: 110, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(quiet ? .gray.opacity(0.3) : .red)
        .help("End the test and save the log")
    }
}

struct RecordingBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
            Text("Logging")
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.red.opacity(0.15), in: Capsule())
        .onAppear { pulse = true }
        .accessibilityLabel("Logging is on")
    }
}

struct MiniStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct ScoreTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title.bold()).foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

struct AnswerTile: View {
    enum State { case idle, correct, wrong, dimmed }

    let label:  String
    let state:  State
    let locked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .background(bgColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .foregroundStyle(fgColor)
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 22, style: .continuous))
                .hoverEffect(.highlight)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(state == .dimmed ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: state)
    }

    private var bgColor: Color {
        switch state {
        case .idle, .dimmed: return Color.blue.opacity(0.16)
        case .correct:       return Color.green.opacity(0.85)
        case .wrong:         return Color.red.opacity(0.85)
        }
    }

    private var fgColor: Color {
        switch state {
        case .idle, .dimmed:   return .primary
        case .correct, .wrong: return .white
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
