//
//  ContentView.swift
//  biometricTracker
//
//  Created by Prisha Marpu on 4/9/26.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 20) {

            // ── Score bar ──────────────────────────────────────────
            HStack(spacing: 0) {
                ScoreTile(label: "Score",   value: "\(appModel.mathManager.score)",        color: .blue)
                Divider().frame(height: 40)
                ScoreTile(label: "Correct", value: "\(appModel.mathManager.correctCount)",  color: .green)
                Divider().frame(height: 40)
                ScoreTile(label: "Wrong",   value: "\(appModel.mathManager.wrongCount)",    color: .red)
                Divider().frame(height: 40)
                ScoreTile(label: "Total",   value: "\(appModel.mathManager.totalAnswered)", color: .primary)
            }
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

            // ── Level badge ────────────────────────────────────────
            Text(appModel.mathManager.currentLevel.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(levelColor.opacity(0.15), in: Capsule())
                .foregroundStyle(levelColor)

            // ── Question ───────────────────────────────────────────
            Text(appModel.mathManager.current.question)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 28)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

            // ── Feedback ───────────────────────────────────────────
            Group {
                if let result = appModel.mathManager.lastCorrect {
                    Text(result ? "✓ Correct!" : "✗ Wrong")
                        .font(.title2.bold())
                        .foregroundStyle(result ? .green : .red)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(" ").font(.title2)
                }
            }
            .animation(.spring(duration: 0.3), value: appModel.mathManager.lastCorrect)

            // ── Answer grid ────────────────────────────────────────
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 14
            ) {
                ForEach(
                    Array(appModel.mathManager.current.answers.enumerated()),
                    id: \.offset
                ) { i, answer in
                    AnswerTile(
                        label:  answer,
                        state:  tileState(for: i),
                        action: { appModel.mathManager.submit(answerIndex: i) }
                    )
                }
            }

            // ── Log panel ──────────────────────────────────────────
            LogPanel(entries: appModel.mathManager.log)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    private var levelColor: Color {
        switch appModel.mathManager.currentLevel {
        case .easy:   return .green
        case .medium: return .orange
        case .hard:   return .red
        }
    }

    private func tileState(for index: Int) -> AnswerTile.State {
        guard let result = appModel.mathManager.lastCorrect else { return .idle }
        if index == appModel.mathManager.current.correctIndex       { return .correct }
        if index == appModel.mathManager.lastAnsweredIndex && !result { return .wrong  }
        return .idle
    }
}

// MARK: - Score tile
struct ScoreTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

// MARK: - Answer tile
struct AnswerTile: View {
    enum State { case idle, correct, wrong }

    let label:  String
    let state:  State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(bgColor, in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(fgColor)
        }
        .buttonStyle(.plain)
        .disabled(state != .idle)
    }

    private var bgColor: Color {
        switch state {
        case .idle:    return Color.blue.opacity(0.12)
        case .correct: return Color.green.opacity(0.85)
        case .wrong:   return Color.red.opacity(0.85)
        }
    }

    private var fgColor: Color {
        switch state {
        case .idle:             return .primary
        case .correct, .wrong:  return .white
        }
    }
}

// MARK: - Log panel
struct LogPanel: View {
    let entries: [LogEntry]
    @State private var exportText = ""
    @State private var isExporting = false
    @State private var exportStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session log")
                    .font(.headline)
                Spacer()
                Text("\(entries.count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Written each time a question appears or an answer is chosen.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: beginExport) {
                Label("Download log", systemImage: "arrow.down.doc")
            }
            .disabled(entries.isEmpty)

            if let exportStatus {
                Text(exportStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            Text(entry.formatted)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(logColor(for: entry.message))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                }
                .onChange(of: entries.count) { _, _ in
                    guard let id = entries.last?.id else { return }
                    withAnimation(.snappy) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .fileExporter(
            isPresented: $isExporting,
            document: LogFile(text: exportText),
            contentType: .plainText,
            defaultFilename: "math-question-log"
        ) { result in
            switch result {
            case .success:
                exportStatus = "Log saved."
            case .failure(let error):
                let nsError = error as NSError
                let cancelled = nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue
                if !cancelled {
                    exportStatus = error.localizedDescription
                }
            }
        }
    }

    private func beginExport() {
        guard !entries.isEmpty else { return }
        exportText = QuestionLogFormat.text(entries: entries)
        isExporting = true
    }

    private func logColor(for message: String) -> Color {
        if message.contains("NEW QUESTION") { return .orange }
        if message.contains("✓") { return .green }
        if message.contains("✗") { return .red }
        return .secondary
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
