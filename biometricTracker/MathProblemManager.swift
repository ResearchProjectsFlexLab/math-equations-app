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

// MARK: - Test Phase
enum TestPhase: Equatable {
    case ready       // before Start is pressed
    case countdown   // Start pressed, logging on, 3-2-1 before first question
    case running     // questions on screen
    case finished    // Stop pressed, logging closed, log ready to download
}

// MARK: - Manager
@MainActor
@Observable
final class MathProblemManager {

    /// Seconds a participant has to answer each question before it counts as missed.
    static let secondsPerQuestion: Double = 20

    var current:           MathProblem = MathProblem.generate(level: .easy)
    var currentLevel:      GameLevel   = .easy
    var score:             Int         = 0
    var correctCount:      Int         = 0
    var wrongCount:        Int         = 0
    var timedOutCount:     Int         = 0
    var totalAnswered:     Int         = 0
    var streak:            Int         = 0
    var lastCorrect:       Bool?       = nil
    var lastAnsweredIndex: Int?        = nil
    var phase:             TestPhase   = .ready
    var countdownValue:    Int         = 0
    var timeRemaining:     Double      = MathProblemManager.secondsPerQuestion
    var questionNumber:    Int         { questionIndex }
    var sessionStartDate:  Date?       = nil
    var sessionEndDate:    Date?       = nil
    var participantID:     String      = ""
    /// Where the log was written when the test stopped (Files › On My Apple Vision Pro › biometricTracker).
    var savedLogURL:       URL?        = nil
    var saveError:         String?     = nil
    var log:               [LogEntry]  = []

    /// True from the moment Start is pressed until Stop is pressed — i.e. while logging is on.
    var isRunning: Bool { phase == .countdown || phase == .running }

    let trial = TrialSession()

    private let questionLogger = Logger(subsystem: "FlexLab.biometricTracker", category: "QuestionLog")

    private var questionSpawnTime: TimeInterval = 0
    private var questionIndex:     Int          = 0
    private var reactionTimesMs:   [Double]     = []
    private var advanceTask:       Task<Void, Never>?
    private var countdownTask:     Task<Void, Never>?
    private var timerTask:         Task<Void, Never>?

    // MARK: - Start / Stop

    /// Starts logging immediately, then shows a countdown before the first question.
    /// Pass `countdown: 0` to show the first question right away.
    func start(countdown: Int = 3) {
        guard !isRunning else { return }
        cancelTasks()
        score = 0
        correctCount = 0
        wrongCount = 0
        timedOutCount = 0
        totalAnswered = 0
        streak = 0
        lastCorrect = nil
        lastAnsweredIndex = nil
        currentLevel = .easy
        questionIndex = 0
        reactionTimesMs = []
        trial.events = []
        trial.lastReactionMs = nil
        log = []
        sessionStartDate = .now
        sessionEndDate = nil
        savedLogURL = nil
        saveError = nil

        let who = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
        addLog("SESSION START — \(formattedDate())" + (who.isEmpty ? "" : " | participant: \(who)"))

        guard countdown > 0 else {
            beginQuestions()
            return
        }

        phase = .countdown
        countdownValue = countdown
        countdownTask = Task {
            for value in stride(from: countdown, through: 1, by: -1) {
                countdownValue = value
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            beginQuestions()
        }
    }

    func stop() {
        guard isRunning else { return }
        cancelTasks()
        phase = .finished
        lastCorrect = nil
        lastAnsweredIndex = nil
        sessionEndDate = .now
        addLog(String(
            format: "SESSION STOP — score: \(score) correct: \(correctCount) wrong: \(wrongCount) timed out: \(timedOutCount) | accuracy: %.0f%% | avg reaction: %.0fms | duration: %.0fs",
            accuracy * 100, averageReactionMs ?? 0, sessionDuration
        ))
        saveLogToFiles()
    }

    /// Writes the log into the app's Documents folder, which the Files app shows,
    /// so nothing is asked of the participant after Stop.
    func saveLogToFiles(directory: URL? = nil) {
        do {
            let folder = try directory ?? FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            var url = folder.appendingPathComponent(suggestedLogFilename).appendingPathExtension("txt")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(suggestedLogFilename)-\(n)").appendingPathExtension("txt")
                n += 1
            }
            try logText.write(to: url, atomically: true, encoding: .utf8)
            savedLogURL = url
            saveError = nil
        } catch {
            savedLogURL = nil
            saveError = error.localizedDescription
        }
    }

    /// Returns to the welcome screen after a finished test.
    func reset() {
        guard !isRunning else { return }
        phase = .ready
    }

    // MARK: - Summary stats

    var accuracy: Double {
        totalAnswered == 0 ? 0 : Double(correctCount) / Double(totalAnswered)
    }

    var averageReactionMs: Double? {
        reactionTimesMs.isEmpty ? nil : reactionTimesMs.reduce(0, +) / Double(reactionTimesMs.count)
    }

    var sessionDuration: TimeInterval {
        guard let sessionStartDate else { return 0 }
        return (sessionEndDate ?? .now).timeIntervalSince(sessionStartDate)
    }

    var logText: String {
        QuestionLogFormat.text(entries: log)
    }

    var suggestedLogFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = f.string(from: sessionStartDate ?? .now)
        let who = participantID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
        return who.isEmpty ? "math-test-log_\(stamp)" : "math-test-log_\(who)_\(stamp)"
    }

    // MARK: - Submit
    func submit(answerIndex: Int) {
        guard phase == .running, lastCorrect == nil,
              current.answers.indices.contains(answerIndex) else { return }
        timerTask?.cancel()

        let isCorrect     = answerIndex == current.correctIndex
        lastCorrect       = isCorrect
        lastAnsweredIndex = answerIndex
        totalAnswered    += 1

        let tapped       = current.answers[answerIndex]
        let responseTime = CACurrentMediaTime()
        let reactionMs   = (responseTime - questionSpawnTime) * 1000.0
        reactionTimesMs.append(reactionMs)

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

        scheduleAdvance()
    }

    /// Called when the per-question timer runs out.
    func timeOut() {
        guard phase == .running, lastCorrect == nil else { return }
        timerTask?.cancel()
        lastCorrect       = false
        lastAnsweredIndex = nil
        totalAnswered    += 1
        wrongCount       += 1
        timedOutCount    += 1
        streak            = 0
        timeRemaining     = 0

        trial.events.append(TrialEvent(
            trialIndex:        questionIndex,
            spawnTimestamp:    questionSpawnTime,
            responseTimestamp: CACurrentMediaTime(),
            dotPosition:       SIMD3<Float>(0, 0, -0.65),
            responded:         false
        ))
        addLog("TIME UP ✗ no answer | correct: '\(current.correctAnswer)' | Q: \(current.question) | limit: \(Int(Self.secondsPerQuestion))s")
        scheduleAdvance()
    }

    // MARK: - Advance
    func advance() {
        guard phase == .running else { return }
        lastCorrect       = nil
        lastAnsweredIndex = nil
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
    private func beginQuestions() {
        phase = .running
        current = MathProblem.generate(level: currentLevel)
        spawnNewQuestion(current)
    }

    private func scheduleAdvance() {
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private func spawnNewQuestion(_ problem: MathProblem) {
        questionSpawnTime = CACurrentMediaTime()
        questionIndex    += 1
        addLog("NEW QUESTION [\(questionIndex)] — \(problem.question) | Level: \(currentLevel.title) | Options: \(problem.answers.joined(separator: ", "))")
        startQuestionTimer()
    }

    private func startQuestionTimer() {
        timerTask?.cancel()
        timeRemaining = Self.secondsPerQuestion
        let spawn = questionSpawnTime
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                let left = Self.secondsPerQuestion - (CACurrentMediaTime() - spawn)
                timeRemaining = max(0, left)
                if left <= 0 {
                    timeOut()
                    return
                }
            }
        }
    }

    private func cancelTasks() {
        advanceTask?.cancel();   advanceTask = nil
        countdownTask?.cancel(); countdownTask = nil
        timerTask?.cancel();     timerTask = nil
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
