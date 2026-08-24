//
//  PendingApprovals.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The approval requests a run is blocked on, tagged with which run they
//  belong to.
//
//  AgentHost kept these in a bare dictionary and swept the whole thing when a
//  run ended. That is only correct if one run exists at a time, and one does
//  not: AgentRunHandle *requests* cancellation, and the cancelled turn keeps
//  executing until it next looks at Task.isCancelled -- almost always after
//  its replacement has already started and put its own approval on screen.
//  The superseded turn's sweep then answered 거부 for a request the user was
//  still looking at.
//
//  Its own type rather than a property on AgentHost for the same reason
//  AgentRunHandle is: AgentHost is a PuckClient-only source the test bundle
//  does not compile, and the run-scoping is the part worth testing.
//

import Foundation

/// Answers are delivered as a plain closure rather than a
/// `CheckedContinuation` so this is testable without suspending anything;
/// AgentHost passes `continuation.resume(returning:)`.
final class PendingApprovals {
    private let lock = NSLock()
    private var waiting: [String: (run: Int, answer: (Bool) -> Void)] = [:]

    /// Registers a request belonging to `run`. A duplicate id replaces the
    /// earlier entry, which would otherwise be leaked unanswered.
    func add(id: String, run: Int, answer: @escaping (Bool) -> Void) {
        lock.lock()
        let displaced = waiting.updateValue((run: run, answer: answer), forKey: id)
        lock.unlock()
        displaced?.answer(false)
    }

    /// The user's own answer. Unknown ids are ignored -- an answer for a
    /// request already swept has nothing left to resume.
    func resolve(id: String, approved: Bool) {
        lock.lock()
        let pending = waiting.removeValue(forKey: id)
        lock.unlock()
        pending?.answer(approved)
    }

    /// Denies what is still waiting, answering `false` rather than leaving a
    /// caller suspended: an approval's caller is a tool that has to return
    /// something, and "not allowed" is the only safe answer on its behalf.
    ///
    /// - Parameter run: deny only this run's requests. nil denies every one,
    ///   which is what 중지 means -- the user stopped the turn on screen, and
    ///   anything an earlier turn stranded goes with it.
    func failAll(run: Int? = nil) {
        lock.lock()
        let swept = waiting.filter { run == nil || $0.value.run == run }
        for id in swept.keys { waiting.removeValue(forKey: id) }
        lock.unlock()
        for (_, pending) in swept { pending.answer(false) }
    }
}
