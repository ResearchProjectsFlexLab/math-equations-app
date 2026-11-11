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
    case ready        // before Start Baseline is pressed
    case practice     // baseline part 1: pick the colour you see, to learn look + pinch
    case relaxBefore  // baseline part 2: 1 minute of calm breathing before the test
    case testIntro    // test instructions, waiting for Start Test
    case countdown    // Start Test pressed, 3-2-1 before first question
    case running      // questions on screen
    case relaxAfter   // 1 minute of calm breathing after the test
    case finished     // logging closed, log saved
}

// MARK: - Colour practice
/// The colours used in the baseline practice. The view maps each to a SwiftUI colour.
enum PracticeColour: String, CaseIterable {
    case red, blue, green, yellow, orange, purple

    var name: String { rawValue.capitalized }
}

struct ColourTrial: Equatable {
    let target:  PracticeColour
    let options: [PracticeColour]

    var correctIndex: Int { options.firstIndex(of: target)! }

    static func generate(avoiding previous: PracticeColour? = nil) -> ColourTrial {
        let target = PracticeColour.allCases.filter { $0 != previous }.randomElement()!
        let others = PracticeColour.allCases.filter { $0 != target }.shuffled().prefix(3)
        return ColourTrial(target: target, options: ([target] + others).shuffled())
    }
}

// MARK: - Manager
@MainActor
@Observable
final class MathProblemManager {

    /// Seconds a participant has to answer each question before it counts as missed.
    static let secondsPerQuestion: Double = 20

    /// The test ends on its own (and saves the log) after this long. Counted from the first question.
    static let testDuration: TimeInterval = 3 * 60

    /// How many colour questions the baseline practice asks.
    static let practiceTrialCount = 5

    /// Length of the calm rest before and after the test.
    static let restDuration: TimeInterval = 60

    // Baseline practice state
    var practiceTrial:        ColourTrial = .generate()
    var practiceNumber:       Int         = 0
    var practiceCorrectCount: Int         = 0
    var practiceLastCorrect:  Bool?       = nil
    var practiceLastIndex:    Int?        = nil

    /// Time left in the current 1-minute rest.
    var restTimeRemaining: TimeInterval = MathProblemManager.restDuration

    /// Time left in the whole test.
    var testTimeRemaining: TimeInterval = MathProblemManager.testDuration

    /// True when the test ended because time ran out, not because Stop was pressed.
    var completedAllQuestions: Bool = false

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

    /// True from the moment Start Baseline is pressed until the session ends — i.e. while logging is on.
    var isRunning: Bool { phase != .ready && phase != .finished }

    let trial = TrialSession()

    private let questionLogger = Logger(subsystem: "FlexLab.biometricTracker", category: "QuestionLog")

    private var questionSpawnTime: TimeInterval = 0
    private var questionIndex:     Int          = 0
    private var reactionTimesMs:   [Double]     = []
    private var advanceTask:       Task<Void, Never>?
    private var countdownTask:     Task<Void, Never>?
    private var timerTask:         Task<Void, Never>?
    private var testClockTask:     Task<Void, Never>?
    private var practiceTask:      Task<Void, Never>?
    private var restTask:          Task<Void, Never>?

    // MARK: - Baseline

    /// Starts logging and the baseline: colour practice, then 1 minute of rest, then the test instructions.
    func startBaseline() {
        guard !isRunning else { return }
        cancelTasks()
        resetSession()
        addLog("BASELINE START — colour practice (\(Self.practiceTrialCount) questions), then \(Int(Self.restDuration))s rest")
        phase = .practice
        practiceNumber = 0
        practiceCorrectCount = 0
        nextPracticeTrial()
    }

    func submitPractice(optionIndex: Int) {
        guard phase == .practice, practiceLastCorrect == nil,
              practiceTrial.options.indices.contains(optionIndex) else { return }
        let picked = practiceTrial.options[optionIndex]
        let correct = picked == practiceTrial.target
        practiceLastCorrect = correct
        practiceLastIndex = optionIndex
        if correct { practiceCorrectCount += 1 }
        addLog("PRACTICE ANSWER [\(practiceNumber)] — '\(picked.name)' \(correct ? "✓ correct" : "✗ wrong | correct: '\(practiceTrial.target.name)'")")

        practiceTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            if practiceNumber >= Self.practiceTrialCount {
                addLog("PRACTICE END — \(practiceCorrectCount)/\(Self.practiceTrialCount) correct")
                startRest(after: false)
            } else {
                nextPracticeTrial()
            }
        }
    }

    private func nextPracticeTrial() {
        practiceLastCorrect = nil
        practiceLastIndex = nil
        practiceTrial = .generate(avoiding: practiceNumber == 0 ? nil : practiceTrial.target)
        practiceNumber += 1
        addLog("PRACTICE QUESTION [\(practiceNumber)] — colour: \(practiceTrial.target.name) | Options: \(practiceTrial.options.map(\.name).joined(separator: ", "))")
    }

    // MARK: - Rest (before and after the test)

    private func startRest(after: Bool) {
        restTask?.cancel()
        phase = after ? .relaxAfter : .relaxBefore
        restTimeRemaining = Self.restDuration
        addLog("REST START — \(after ? "after" : "before") test | \(Int(Self.restDuration))s")
        let began = CACurrentMediaTime()
        restTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                let left = Self.restDuration - (CACurrentMediaTime() - began)
                restTimeRemaining = max(0, left)
                if left <= 0 {
                    endRest()
                    return
                }
            }
        }
    }

    /// Ends the current rest. Called by the rest timer; tests can call it to skip the wait.
    func endRest() {
        switch phase {
        case .relaxBefore:
            restTask?.cancel(); restTask = nil
            restTimeRemaining = 0
            addLog("REST END — before test")
            phase = .testIntro
        case .relaxAfter:
            restTask?.cancel(); restTask = nil
            restTimeRemaining = 0
            addLog("REST END — after test")
            stop()
        default:
            break
        }
    }

    // MARK: - Start / Stop

    /// Starts the math test with a countdown before the first question.
    /// From the test instructions screen this continues the baseline's log; from the
    /// welcome screen it starts a fresh log without a baseline.
    /// Pass `countdown: 0` to show the first question right away.
    func start(countdown: Int = 3) {
        guard phase == .ready || phase == .finished || phase == .testIntro else { return }
        cancelTasks()
        if phase == .testIntro {
            resetTestScores()
            addLog("TEST START — \(Int(Self.testDuration / 60)) minute math test")
        } else {
            resetSession()
        }

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

    /// Clears everything and opens a new log with SESSION START.
    private func resetSession() {
        resetTestScores()
        log = []
        sessionStartDate = .now
        sessionEndDate = nil
        savedLogURL = nil
        saveError = nil

        let who = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
        addLog("SESSION START — \(formattedDate())" + (who.isEmpty ? "" : " | participant: \(who)"))
    }

    private func resetTestScores() {
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
        completedAllQuestions = false
        testTimeRemaining = Self.testDuration
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
    /// Ends the test because the time limit was reached, then starts the 1-minute rest.
    /// The log is saved automatically when the rest ends.
    func endBecauseTimeIsUp() {
        guard phase == .running else { return }
        cancelTasks()
        completedAllQuestions = true
        testTimeRemaining = 0
        lastCorrect = nil
        lastAnsweredIndex = nil
        addLog("SESSION COMPLETE — \(Int(Self.testDuration / 60)) minute time limit reached")
        startRest(after: true)
    }

    private func beginQuestions() {
        phase = .running
        startTestClock()
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

    private func startTestClock() {
        testClockTask?.cancel()
        testTimeRemaining = Self.testDuration
        let began = CACurrentMediaTime()
        testClockTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                let left = Self.testDuration - (CACurrentMediaTime() - began)
                testTimeRemaining = max(0, left)
                if left <= 0 {
                    endBecauseTimeIsUp()
                    return
                }
            }
        }
    }

    private func cancelTasks() {
        advanceTask?.cancel();   advanceTask = nil
        countdownTask?.cancel(); countdownTask = nil
        timerTask?.cancel();     timerTask = nil
        testClockTask?.cancel(); testClockTask = nil
        practiceTask?.cancel();  practiceTask = nil
        restTask?.cancel();      restTask = nil
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
