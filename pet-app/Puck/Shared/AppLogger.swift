//
//  AppLogger.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Shared logging utility (~/Library/Application Support/Puck/logs/)
//
//  General app diagnostics — distinct from ToolExecutionLogger (F11), which
//  writes the specific protocol section 7 tool_exec_start/end format joinable
//  across agent/pet-app/workspace logs. This one is just "what happened".

import Foundation

enum LogLevel: String, Encodable {
    case debug, info, warning, error
}

struct AppLogLine: Encodable {
    let ts: String
    let level: LogLevel
    let message: String
}

/// Thin file-I/O wrapper — not unit tested beyond what AppLogLine's plain
/// Encodable conformance already guarantees.
final class AppLogger {
    /// `nonisolated(unsafe)` because it is deliberately shared: this is
    /// called from tool executors, socket queues and the frame loop, and
    /// everything it does goes through JSONLinesFileAppender's own serial
    /// queue. Pinning it to an actor would mean the one thing that records a
    /// failure could not be called from wherever the failure happened.
    nonisolated(unsafe) static let shared = AppLogger(
        directory: isRunningTests ? testLogDirectory : defaultLogDirectory
    )

    static let defaultLogDirectory = JSONLinesFileAppender.defaultLogDirectory

    /// The test bundle exercises SpriteAvatar, CharacterController and the
    /// rest with throwaway fixtures, and every failure they log went into the
    /// *real* diagnostics log -- "Failed to load avatar sprite at /var/.../
    /// walk.png" and "unregistered StateKind walk" appeared there on every
    /// `xcodebuild test`, indistinguishable from something the running app
    /// had hit. Tests write to a temp directory instead.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let testLogDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PuckTestLogs", isDirectory: true)

    private let appender: JSONLinesFileAppender

    init(directory: URL = AppLogger.defaultLogDirectory) {
        appender = JSONLinesFileAppender(directory: directory, queueLabel: "Puck.AppLogger")
    }

    func log(_ level: LogLevel, _ message: String) {
        appender.append(AppLogLine(ts: ISO8601DateFormatter().string(from: Date()), level: level, message: message))
    }
}
