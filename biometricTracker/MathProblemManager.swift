//
//  MathProblemManager.swift
//  biometricTracker
//
//  Created by Prisha Marpu on 4/23/26.
//


import Foundation
import Observation
import os
import simd
import QuartzCore

// MARK: - Log Entry
struct LogEntry: Identifiable, Codable {
    let id        = UUID()
    let timestamp = Date()
    let message:  String

    var eventType: String { QuestionLogFormat.parseEventType(from: message) }

    var formatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return "[\(f.string(from: timestamp))] \(message)"
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, message
    }
}

// MARK: - Game Level
enum GameLevel: Int, CaseIterable {
    case easy   = 1
    case medium = 2
    case hard   = 3

    var title: String {
        switch self {
        case .easy:   return "Level 1 — Single Digit"
        case .medium: return "Level 2 — Double Digit"
        case .hard:   return "Level 3 — Equations"
        }
    }
}

// MARK: - Math Problem
struct MathProblem: Identifiable {
    let id            = UUID()
    let question:     String
    let answers:      [String]
    let correctIndex: Int
    let level:        GameLevel

    var correctAnswer: String { answers[correctIndex] }
}

// MARK: - Manager
@MainActor
@Observable
final class MathProblemManager {

    var current:           MathProblem = MathProblem.generate(level: .easy)
    var currentLevel:      GameLevel   = .easy
    var score:             Int         = 0
    var correctCount:      Int         = 0
    var wrongCount:        Int         = 0
    var totalAnswered:     Int         = 0
    var streak:            Int         = 0
    var lastCorrect:       Bool?       = nil
    var lastAnsweredIndex: Int?        = nil
    var log:               [LogEntry]  = []

    let trial = TrialSession()

    private let questionLogger = Logger(subsystem: "FlexLab.biometricTracker", category: "QuestionLog")

    private var questionSpawnTime: TimeInterval = 0
    private var questionIndex:     Int          = 0

    init() {
        addLog("SESSION START — \(formattedDate())")
        spawnNewQuestion(current)
    }

    // MARK: - Submit
    func submit(answerIndex: Int) {
        guard lastCorrect == nil else { return }

        let isCorrect     = answerIndex == current.correctIndex
        lastCorrect       = isCorrect
        lastAnsweredIndex = answerIndex
        totalAnswered    += 1

        let tapped       = current.answers[answerIndex]
        let responseTime = CACurrentMediaTime()
        let reactionMs   = (responseTime - questionSpawnTime) * 1000.0

        let event = TrialEvent(
            trialIndex:        questionIndex,
            spawnTimestamp:    questionSpawnTime,
            responseTimestamp: responseTime,
            dotPosition:       SIMD3<Float>(0, 0, -0.65),
            responded:         true
        )
        trial.events.append(event)
        trial.lastReactionMs = event.reactionTimeMs

        if isCorrect {
            score        += pointValue()
            correctCount += 1
            streak       += 1
            addLog(String(
                format: "ANSWER SELECTED — '\(tapped)' ✓ correct | Q: \(current.question) | reaction: %.0fms | score: \(score) | streak: \(streak)",
                reactionMs
            ))
        } else {
            wrongCount += 1
            streak      = 0
            addLog(String(
                format: "ANSWER SELECTED — '\(tapped)' ✗ wrong | correct: '\(current.correctAnswer)' | Q: \(current.question) | reaction: %.0fms",
                reactionMs
            ))
        }

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            lastCorrect       = nil
            lastAnsweredIndex = nil
            advance()
        }
    }

    // MARK: - Advance
    func advance() {
        let oldLevel = currentLevel
        if correctCount >= 10     { currentLevel = .hard   }
        else if correctCount >= 5 { currentLevel = .medium }
        else                      { currentLevel = .easy   }

        if currentLevel != oldLevel {
            addLog("LEVEL CHANGE — \(oldLevel.title) → \(currentLevel.title)")
        }

        let next = MathProblem.generate(level: currentLevel)
        current  = next
        spawnNewQuestion(next)
    }

    // MARK: - Gaze logging
    func logGaze(x: Float, y: Float, z: Float) {
        addLog(String(format: "GAZE COORDINATES — x:%.4f y:%.4f z:%.4f", x, y, z))
    }

    func logGazeOnAnswer(_ answer: String) {
        addLog("GAZE ON ANSWER — '\(answer)'")
    }

    func logGazeIdle() {
        addLog("GAZE IDLE — no answer focused")
    }

    // MARK: - Helpers
    private func spawnNewQuestion(_ problem: MathProblem) {
        questionSpawnTime = CACurrentMediaTime()
        questionIndex    += 1
        addLog("NEW QUESTION [\(questionIndex)] — \(problem.question) | Level: \(currentLevel.title) | Options: \(problem.answers.joined(separator: ", "))")
    }

    var logText: String {
        QuestionLogFormat.text(entries: log)
    }

    func addLog(_ message: String) {
        let entry = LogEntry(message: message)
        log.append(entry)
        let line = entry.formatted
        questionLogger.info("\(line, privacy: .public)")
    }

    private func pointValue() -> Int {
        switch currentLevel {
        case .easy:   return 1
        case .medium: return 2
        case .hard:   return 3
        }
    }

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}

// MARK: - Problem Generation
extension MathProblem {

    static func generate(level: GameLevel) -> MathProblem {
        switch level {
        case .easy:   return singleDigit()
        case .medium: return doubleDigit()
        case .hard:   return equation()
        }
    }

    private static func singleDigit() -> MathProblem {
        let a   = Int.random(in: 1...9)
        let b   = Int.random(in: 1...9)
        let ops: [(String, Int)] = [("+", a+b), ("-", abs(a-b)), ("×", a*b)]
        let (op, answer) = ops.randomElement()!
        let question = op == "-"
            ? "\(max(a,b)) - \(min(a,b)) = ?"
            : "\(a) \(op) \(b) = ?"
        return makeChoices(question: question, correct: answer, spread: 3, level: .easy)
    }

    private static func doubleDigit() -> MathProblem {
        let a      = Int.random(in: 10...99)
        let b      = Int.random(in: 10...99)
        let useAdd = Bool.random()
        let question = useAdd ? "\(a) + \(b) = ?" : "\(max(a,b)) - \(min(a,b)) = ?"
        let answer   = useAdd ? a + b : abs(a - b)
        return makeChoices(question: question, correct: answer, spread: 10, level: .medium)
    }

    private static func equation() -> MathProblem {
        let a = Int.random(in: 2...5)
        let x = Int.random(in: 1...9)
        let b = Int.random(in: 1...10)
        let c = a * x + b
        return makeChoices(
            question: "\(a)x + \(b) = \(c),  find x",
            correct:  x, spread: 3, level: .hard
        )
    }

    private static func makeChoices(
        question: String, correct: Int,
        spread: Int, level: GameLevel
    ) -> MathProblem {
        var distractors = Set<Int>()
        var attempts    = 0
        while distractors.count < 3 && attempts < 60 {
            let offset    = Int.random(in: 1...spread) * (Bool.random() ? 1 : -1)
            let candidate = correct + offset
            if candidate != correct && candidate >= 0 {
                distractors.insert(candidate)
            }
            attempts += 1
        }
        var pad = 1
        while distractors.count < 3 {
            if correct + pad != correct { distractors.insert(correct + pad) }
            pad += 1
        }
        let shuffled     = ([correct] + Array(distractors)).shuffled().map(String.init)
        let correctIndex = shuffled.firstIndex(of: String(correct))!
        return MathProblem(question: question, answers: shuffled,
                           correctIndex: correctIndex, level: level)
    }
}
