//
//  AgentRunHandle.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Holds the Task of the agent turn that is currently running, so the chat's
//  중지 button has something to cancel.
//
//  AgentHost used to start a turn with a bare fire-and-forget `Task {}` and
//  keep no reference to it, which meant 중지 could deny pending approvals and
//  stop a code_editor run but could not stop the turn that owned them -- the
//  model kept answering into a transcript the user had already stopped. This
//  is the missing handle, kept as its own type (rather than a property on
//  AgentHost) because AgentHost is a PuckClient-only source that the test
//  bundle does not compile, and the start/cancel/finish bookkeeping is the
//  part worth testing.
//

import Foundation

final class AgentRunHandle {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    /// Which start this is. A run only clears the handle when it is still the
    /// current one -- otherwise a slow run finishing after a newer one started
    /// would drop the newer run's task and leave 중지 with nothing to cancel.
    private var generation = 0
    private var finishedGeneration = 0

    /// Whether a run is being held right now. `false` once it finishes or is
    /// cancelled.
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return task != nil
    }

    /// Runs `body` as the active turn. Any run still held is cancelled first:
    /// one session answers one command at a time, and a second command
    /// arriving means the first is no longer what the user is waiting for.
    @discardableResult
    func start(_ body: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        lock.lock()
        let previous = task
        task = nil
        generation += 1
        let mine = generation
        lock.unlock()
        previous?.cancel()

        let created = Task { [weak self] in
            await body()
            self?.finish(generation: mine)
        }
        lock.lock()
        // `body` can finish before this line is reached, in which case the
        // handle is already clear and storing the task would leave a completed
        // run looking live forever.
        if finishedGeneration < mine { task = created }
        lock.unlock()
        return created
    }

    /// The 중지 button. Cancelling is all this does -- the run itself is
    /// responsible for noticing (AgentRunner checks Task.isCancelled between
    /// steps) and for ending the transcript honestly.
    func cancel() {
        lock.lock()
        let current = task
        task = nil
        lock.unlock()
        current?.cancel()
    }

    private func finish(generation: Int) {
        lock.lock()
        finishedGeneration = max(finishedGeneration, generation)
        if self.generation == generation { task = nil }
        lock.unlock()
    }
}
