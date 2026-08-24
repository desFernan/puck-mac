//
//  AcpCodeEditorSession.swift
//  Puck
//
//  One code_editor run. The protocol half -- initialize -> session/new ->
//  session/prompt, streaming session/update and answering
//  session/request_permission -- lives in AcpTurnSession, which a CLI-backed
//  chat turn drives the same way. What is left here is what makes a run a
//  *code_editor* run: retaining a protocol-level audit of attempted writes
//  outside the project, and turning the turn's outcome into the result a tool
//  executor reports. AcpAgentProcess enforces the boundary at the OS layer.
//

import Foundation

struct CodeEditorResult: Equatable {
    var ok: Bool
    var summary: String
    var changedFiles: [String]
    var error: String?
    var detail: String?

    static func cancelled(changedFiles: [String] = []) -> CodeEditorResult {
        CodeEditorResult(ok: false, summary: Strings.text(.acpAborted), changedFiles: changedFiles, error: "cancelled")
    }

    /// What the tool_result should carry as its `detail`.
    ///
    /// On a failure the summary is the half written for a person ("claude CLI를
    /// 찾을 수 없습니다…") and `detail` the half written for a machine
    /// (`vendorCLINotFound(...)`, a stderr tail). Reporting only `detail` --
    /// which is what `detail ?? summary` did, since `detail` is set on every
    /// failing path -- meant the model and the transcript never saw the
    /// sentence that explains what to do. Summary first so the first line is
    /// the readable one: that line is all a collapsed tool row shows.
    var reportedDetail: String? {
        guard !ok else { return detail }
        var lines: [String] = []
        for part in [summary, detail] {
            guard let part, !part.isEmpty, !lines.contains(part) else { continue }
            lines.append(part)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

final class AcpCodeEditorSession {
    private let projectPath: String
    private let turn: AcpTurnSession

    private let lock = NSLock()
    /// Write-shaped locations the agent reported outside the project. This is
    /// defense-in-depth and user-facing evidence; the child sandbox blocks the
    /// filesystem write itself.
    private var writesOutsideProject: Set<String> = []

    init(
        connection: AcpConnection,
        projectPath: String,
        onUpdate: @escaping (AcpSessionUpdate) -> Void = { _ in },
        resolvePermission: @escaping AcpPermissionResolver = { _ in false },
        stderrTail: @escaping () -> String = { "" }
    ) {
        self.projectPath = projectPath
        // Declared before `turn` so the turn's update hook can call it, and
        // assigned after, once `self` exists to weakly capture.
        var noteWrites: ((AcpSessionUpdate) -> Void)?
        self.turn = AcpTurnSession(
            connection: connection,
            cwd: projectPath,
            onUpdate: { update in
                noteWrites?(update)
                onUpdate(update)
            },
            resolvePermission: resolvePermission,
            stderrTail: stderrTail
        )
        noteWrites = { [weak self] update in
            guard let self else { return }
            let escaped = AcpEventMapping.writesOutside(root: projectPath, in: update)
            guard !escaped.isEmpty else { return }
            self.lock.lock()
            for path in escaped { self.writesOutsideProject.insert(path) }
            self.lock.unlock()
        }
    }

    /// Runs the turn to completion. Errors are returned as a failed
    /// CodeEditorResult rather than thrown -- every caller is a tool executor
    /// that has to report *something* back to the model.
    func run(task: String) async -> CodeEditorResult {
        switch await turn.run(prompt: task) {
        case .cancelled:
            return .cancelled()
        case .failed(let failure):
            return CodeEditorResult(
                ok: false,
                summary: Strings.text(.acpTaskFailed),
                changedFiles: [],
                error: "acp_error",
                detail: failure.text
            )
        case .completed(let completion):
            let escaped = currentWritesOutsideProject()
            guard escaped.isEmpty else {
                // Reported as a failure rather than a footnote on a success:
                // the run wrote where it was not asked to, and the user has to
                // know which paths to go look at.
                return CodeEditorResult(
                    ok: false,
                    summary: Strings.text(.acpWroteOutsideProject),
                    changedFiles: [],
                    error: "wrote_outside_project",
                    detail: escaped.sorted().joined(separator: "\n")
                )
            }
            return CodeEditorResult(
                ok: true,
                summary: completion.text.isEmpty
                    ? String(format: Strings.text(.acpTaskDoneFormat), "\(completion.stopReason)")
                    : completion.text,
                changedFiles: []
            )
        }
    }

    /// Asks the agent to stop. Idempotent -- cancelling twice, or cancelling
    /// before session/new has returned, both do the right thing.
    func cancel() {
        turn.cancel()
    }

    private func currentWritesOutsideProject() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return writesOutsideProject
    }
}
