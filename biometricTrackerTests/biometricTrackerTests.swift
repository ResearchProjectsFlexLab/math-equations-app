//
//  biometricTrackerTests.swift
//  biometricTrackerTests
//
//  Created by Prisha Marpu on 4/9/26.
//

import Foundation
import Testing
@testable import biometricTracker

struct biometricTrackerTests {

    @Test @MainActor func questionsWaitUntilStartAndStopEndsTheRound() {
        let game = MathProblemManager()
        #expect(!game.isRunning)
        #expect(game.log.isEmpty)

        game.submit(answerIndex: 0)
        #expect(game.totalAnswered == 0)

        game.start(countdown: 0)
        #expect(game.isRunning)
        #expect(game.log.contains { $0.message.hasPrefix("SESSION START") })
        #expect(game.log.contains { $0.message.hasPrefix("NEW QUESTION") })

        game.stop()
        #expect(!game.isRunning)
        #expect(game.log.contains { $0.message.hasPrefix("SESSION STOP") })

        let questions = game.log.filter { $0.message.hasPrefix("NEW QUESTION") }.count
        game.advance()
        game.submit(answerIndex: 0)
        #expect(game.log.filter { $0.message.hasPrefix("NEW QUESTION") }.count == questions)
        #expect(game.totalAnswered == 0)
    }

    @Test @MainActor func startLogsImmediatelyEvenDuringCountdown() throws {
        let game = MathProblemManager()
        game.start()
        #expect(game.phase == .countdown)
        #expect(game.isRunning)
        #expect(game.log.contains { $0.message.hasPrefix("SESSION START") })
        #expect(!game.log.contains { $0.message.hasPrefix("NEW QUESTION") })

        game.stop()
        #expect(game.phase == .finished)
        #expect(game.logText.contains("SESSION STOP"))

        // Stop saves the log on its own — no save dialog.
        let url = try #require(game.savedLogURL)
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains("SESSION STOP"))
        try? FileManager.default.removeItem(at: url)
    }

    @Test @MainActor func timeOutCountsAsWrongAndIsLogged() {
        let game = MathProblemManager()
        game.participantID = "P 01"
        game.start(countdown: 0)
        game.timeOut()
        #expect(game.wrongCount == 1)
        #expect(game.timedOutCount == 1)
        #expect(game.log.contains { $0.message.hasPrefix("TIME UP") })
        #expect(game.suggestedLogFilename.hasPrefix("math-test-log_P-01_"))
        game.stop()
        if let url = game.savedLogURL { try? FileManager.default.removeItem(at: url) }
    }

    @Test @MainActor func testEndsAndSavesWhenTimeIsUp() throws {
        #expect(MathProblemManager.testDuration == 180)
        let game = MathProblemManager()
        game.start(countdown: 0)
        #expect(game.testTimeRemaining == MathProblemManager.testDuration)

        game.endBecauseTimeIsUp()
        // A 1-minute rest follows the test; the log is saved when it ends.
        #expect(game.phase == .relaxAfter)
        #expect(game.savedLogURL == nil)
        game.endRest()
        #expect(game.phase == .finished)
        #expect(game.completedAllQuestions)
        #expect(game.testTimeRemaining == 0)
        #expect(game.log.contains { $0.message.hasPrefix("SESSION COMPLETE") })

        // Saved automatically, nothing to press.
        let url = try #require(game.savedLogURL)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("SESSION STOP"))
        try? FileManager.default.removeItem(at: url)

        // No more questions after time is up.
        let questions = game.log.filter { $0.message.hasPrefix("NEW QUESTION") }.count
        game.advance()
        #expect(game.log.filter { $0.message.hasPrefix("NEW QUESTION") }.count == questions)
    }

    @Test @MainActor func baselineStartsWithRestAndStopSavesLog() throws {
        let game = MathProblemManager()
        game.startBaseline()
        #expect(game.phase == .relaxBefore)
        #expect(game.isRunning)
        #expect(game.log.contains { $0.message.hasPrefix("BASELINE START") })
        #expect(game.log.contains { $0.message.hasPrefix("REST START") })

        game.stop()
        #expect(game.phase == .finished)
        let url = try #require(game.savedLogURL)
        try? FileManager.default.removeItem(at: url)
    }

    @Test @MainActor func startTestFromIntroKeepsBaselineLog() {
        let game = MathProblemManager()
        game.startBaseline()
        // Skip the 1-minute rest timer.
        game.endRest()
        #expect(game.phase == .testIntro)

        game.start(countdown: 0)
        #expect(game.phase == .running)
        #expect(game.log.contains { $0.message.hasPrefix("BASELINE START") })
        #expect(game.log.contains { $0.message.hasPrefix("REST END") })
        #expect(game.log.contains { $0.message.hasPrefix("TEST START") })
        #expect(game.log.filter { $0.message.hasPrefix("SESSION START") }.count == 1)

        game.stop()
        if let url = game.savedLogURL { try? FileManager.default.removeItem(at: url) }
    }
}
