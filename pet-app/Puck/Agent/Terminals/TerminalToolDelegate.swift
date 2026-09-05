//
//  TerminalToolDelegate.swift
//  Puck
//
//  The four terminal tools, answered.
//
//  Here rather than in PuckClient, for the reason EditorFileDelegate is here:
//  PuckTests compiles the Puck target, so anything worth testing has to be
//  somewhere `@testable import Puck` can reach. AgentHost keeps the wiring
//  and this keeps the decisions.
//

import Foundation

final class TerminalToolDelegate {
    private let terminals: AgentTerminals
    /// Where a terminal starts. The workspace's own project, resolved when the
    /// tool is called rather than held: the user switches workspaces between
    /// turns, and a shell that opened in the one before is a shell in the
    /// wrong repository.
    private let resolveProjectPath: () -> String?

    init(terminals: AgentTerminals, resolveProjectPath: @escaping () -> String?) {
        self.terminals = terminals
        self.resolveProjectPath = resolveProjectPath
    }

    func handle(tool: String, arguments: JSONValue) -> DispatchedToolResult {
        switch tool {
        case AgentRunner.terminalStartToolName: return start(arguments)
        case AgentRunner.terminalReadToolName: return read(arguments)
        case AgentRunner.terminalSendToolName: return send(arguments)
        case AgentRunner.terminalStopToolName: return stop(arguments)
        default:
            return Self.failure("unknown_tool", tool)
        }
    }

    // MARK: - The four

    private func start(_ arguments: JSONValue) -> DispatchedToolResult {
        guard let command = Self.string("command", in: arguments) else {
            return Self.failure("execution_failed", Strings.text(.terminalNeedsACommand))
        }
        guard let root = resolveProjectPath() else {
            return Self.failure("execution_failed", Strings.text(.terminalNeedsAProject))
        }
        do {
            let session = try terminals.start(command: command, workingDirectory: root)
            // The id and nothing else that looks like output: a start that
            // answered with the first line would invite the model to treat it
            // as the whole answer and never read again.
            return DispatchedToolResult(ok: true, data: .object([
                "id": .string(session.id),
                "command": .string(session.command),
            ]), error: nil, detail: nil)
        } catch {
            return Self.failure("execution_failed", Self.describe(error))
        }
    }

    private func read(_ arguments: JSONValue) -> DispatchedToolResult {
        guard let id = Self.string("id", in: arguments) else {
            return Self.failure("execution_failed", Strings.text(.terminalNeedsAnId))
        }
        do {
            let (read, summary) = try terminals.read(id: id)
            var fields: [String: JSONValue] = [
                "output": .string(read.text),
                "running": .bool(summary.isRunning),
            ]
            if let code = summary.exitCode { fields["exit_code"] = .number(Double(code)) }
            // Said rather than left to be inferred from a gap: a log with a
            // hole in it that does not say so is worse than one that does.
            if read.droppedBytes > 0 {
                fields["dropped_bytes"] = .number(Double(read.droppedBytes))
            }
            return DispatchedToolResult(ok: true, data: .object(fields), error: nil, detail: nil)
        } catch {
            return Self.failure("execution_failed", Self.describe(error))
        }
    }

    private func send(_ arguments: JSONValue) -> DispatchedToolResult {
        guard let id = Self.string("id", in: arguments) else {
            return Self.failure("execution_failed", Strings.text(.terminalNeedsAnId))
        }
        guard let text = Self.string("text", in: arguments, allowingEmpty: true) else {
            return Self.failure("execution_failed", Strings.text(.terminalNeedsText))
        }
        do {
            try terminals.send(id: id, text: text)
            return DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        } catch {
            return Self.failure("execution_failed", Self.describe(error))
        }
    }

    /// With no id, all of them. That is the shape the model needs at the end
    /// of a task -- it started three things and wants them gone, and making
    /// it stop each by id is three chances to leave one running.
    private func stop(_ arguments: JSONValue) -> DispatchedToolResult {
        guard let id = Self.string("id", in: arguments) else {
            terminals.stopAll()
            return DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        }
        do {
            try terminals.stop(id: id)
            return DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        } catch {
            return Self.failure("execution_failed", Self.describe(error))
        }
    }

    // MARK: - Reading arguments

    /// A string argument, trimmed, or nil when it is missing or blank.
    ///
    /// - Parameter allowingEmpty: for `text`, where a blank line is a real
    ///   answer -- pressing return at a prompt is a thing people do.
    static func string(_ key: String, in arguments: JSONValue, allowingEmpty: Bool = false) -> String? {
        guard case .object(let fields) = arguments, case .string(let value)? = fields[key] else { return nil }
        if allowingEmpty { return value }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func failure(_ code: String, _ detail: String) -> DispatchedToolResult {
        DispatchedToolResult(ok: false, data: nil, error: code, detail: detail)
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
