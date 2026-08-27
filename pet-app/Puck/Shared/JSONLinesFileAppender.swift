//
//  JSONLinesFileAppender.swift
//  Puck
//
//  One JSON object per line, appended to a UTC-dated .jsonl file.
//
//  AppLogger and ToolExecutionLogger write different lines into the same
//  directory -- protocol section 7 joins the agent's tool_call to pet-app's
//  tool_exec_start by `id`, so both halves have to land in the same file for
//  the same day. They had the dating, the directory creation and the append
//  written out twice, which is two places for a fix to only half-land.
//

import Foundation

final class JSONLinesFileAppender {
    private let directory: URL
    private let queue: DispatchQueue

    /// The queue is per-appender rather than shared: two loggers writing the
    /// same file still serialize per-line through the filesystem, and giving
    /// each its own queue keeps a slow write on one from delaying the other.
    init(directory: URL, queueLabel: String) {
        self.directory = directory
        queue = DispatchQueue(label: queueLabel)
    }

    /// Fire-and-forget. A log line is never worth propagating a failure to
    /// the caller -- a diagnostics write that throws would turn a logged
    /// problem into a second one.
    ///
    /// Encoded here and written on the queue. The other way round meant
    /// handing an arbitrary Encodable to another thread, which is both
    /// something the compiler cannot check and something the caller may still
    /// be mutating. Bytes are safe to send anywhere.
    func append(_ line: some Encodable) {
        guard let encoded = try? JSONEncoder().encode(line) else { return }
        // A `let`, so what crosses to the queue is a value rather than a
        // variable this thread could still be writing.
        let data = encoded + Data([0x0A])
        queue.async { [directory, data] in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(Self.fileName(for: Date()))

            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    /// UTC, so one file covers the same 24 hours no matter where the machine
    /// is or whether it moved.
    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + ".jsonl"
    }

    /// The logs directory both apps write to.
    static let defaultLogDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }()
}
