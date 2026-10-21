//
//  LogExporter.swift
//  biometricTracker
//
//  Created by Prisha Marpu on 4/23/26.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum QuestionLogFormat {
    static func text(entries: [LogEntry], generatedAt: Date = .now) -> String {
        var lines = [
            "Math Questions log",
            "Generated: \(stamp(generatedAt))",
            "Entries: \(entries.count)",
            "A line is written each time a question appears or an answer is chosen.",
            "",
        ]
        lines.append(contentsOf: entries.map(\.formatted))
        return lines.joined(separator: "\n")
    }

    static func stamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: false))
    }

    static func parseEventType(from message: String) -> String {
        if message.hasPrefix("ANSWER SELECTED") { return "answer_selected" }
        if message.hasPrefix("NEW QUESTION") { return "new_question" }
        if message.hasPrefix("GAZE ON ANSWER") { return "gaze_on_answer" }
        if message.hasPrefix("GAZE COORDINATES") { return "gaze_coordinates" }
        if message.hasPrefix("GAZE IDLE") { return "gaze_idle" }
        if message.hasPrefix("LEVEL CHANGE") { return "level_change" }
        if message.hasPrefix("SESSION START") { return "session_start" }
        return "other"
    }
}

nonisolated struct LogFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
