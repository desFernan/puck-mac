//
//  AgentConversations.swift
//  Puck
//
//  What the model has been told, per chat.
//
//  One runner serves every chat, so the message stacks have to be kept apart
//  by session -- without that they would share one context and the model
//  would answer a question from the chat next door. Alongside each stack sits
//  the workspace last announced to it, so a ten-turn conversation does not
//  accumulate ten identical system lines and a chat opened later under a
//  different workspace still hears about its own.
//
//  Every access is behind one lock, because the callers are not on one queue:
//  a run executes on whatever executor its task landed on, `forgetSession`
//  arrives from the window on main, and a run being replaced keeps going
//  until it notices. The check-and-write in `markAnnounced` is one step for
//  the same reason -- two turns in a chat that both read "not announced"
//  would each append the same system line.
//
//  Lifted out of AgentRunner, which held these two dictionaries and their
//  queue among the tool loop, the approval gate and the event sink. Nothing
//  here is about running a turn, and the one rule with teeth in it -- what
//  trimming is allowed to throw away -- could not be tested through a runner
//  without driving a whole conversation to get there.
//
//  `@unchecked Sendable`: every stored property is reached only inside
//  `lock`.
//

import Foundation

final class AgentConversations: @unchecked Sendable {
    /// How many non-system messages a chat keeps.
    ///
    /// Nothing trimmed the stack before, so a long chat grew every turn until
    /// it hit the model's context limit -- which surfaces to the user as an
    /// unexplained API error partway through a conversation that had been
    /// working.
    static let maximumMessages = 60

    private let systemPrompt: GPTMessage
    private var stacks: [String: [GPTMessage]] = [:]
    private var announced: [String: AgentRunner.WorkspaceContext] = [:]
    private let lock = NSLock()

    init(systemPrompt: String) {
        self.systemPrompt = .system(systemPrompt)
    }

    /// A chat's messages, which is the system prompt alone until it has said
    /// anything.
    func messages(in key: String) -> [GPTMessage] {
        lock.lock()
        defer { lock.unlock() }
        return stacks[key] ?? [systemPrompt]
    }

    func append(_ message: GPTMessage, to key: String) {
        lock.lock()
        defer { lock.unlock() }
        stacks[key, default: [systemPrompt]].append(message)
    }

    /// Gives a chat back the conversation it had before the app was quit.
    ///
    /// Only when it has none: a chat the model has already been talking in
    /// this session must not have a restored copy of itself pushed underneath
    /// what it just said. So this is the one-shot seed for a chat read off
    /// disk, and a no-op for every other.
    ///
    /// What is seeded is prose, not the whole stack -- see
    /// `ChatSession.spokenHistory` for why a restored tool call is a way to
    /// break every message sent in the chat afterwards.
    ///
    /// - Returns: whether it seeded anything, which is also "was this chat
    ///   restored".
    @discardableResult
    func seedIfEmpty(_ history: [(isUser: Bool, text: String)], to key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard stacks[key] == nil, !history.isEmpty else { return false }
        stacks[key] = [systemPrompt] + history.map { $0.isUser ? .user($0.text) : .assistant(text: $0.text, toolCalls: [], reasoning: nil) }
        return true
    }

    /// Gives `destination` the conversation `source` has, for the one case
    /// where a new chat is a continuation rather than a beginning: the agent
    /// branching its work into a task session.
    func carry(from source: String, to destination: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let stack = stacks[source] else { return }
        stacks[destination] = stack
        announced[destination] = announced[source]
    }

    /// Drops the oldest turns once a chat is over the cap.
    ///
    /// System lines are kept whatever their age -- there are a handful of
    /// them (the prompt, and one per workspace the chat has seen) and losing
    /// one would silently un-tell the model something it was told once. The
    /// head of what is kept is never a tool result: the API rejects one whose
    /// assistant tool_calls message has been trimmed away above it.
    func trim(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        let stack = stacks[key] ?? [systemPrompt]
        var systems: [GPTMessage] = []
        var rest: [GPTMessage] = []
        for message in stack {
            if case .system = message { systems.append(message) } else { rest.append(message) }
        }
        guard rest.count > Self.maximumMessages else { return }
        var kept = Array(rest.suffix(Self.maximumMessages))
        while let first = kept.first, case .tool = first { kept.removeFirst() }
        stacks[key] = systems + kept
    }

    /// Drops a deleted chat. The user threw it away; the model should not
    /// still be holding it.
    func forget(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        stacks.removeValue(forKey: key)
        announced.removeValue(forKey: key)
    }

    func forgetEverything() {
        lock.lock()
        defer { lock.unlock() }
        stacks.removeAll()
        announced.removeAll()
    }

    /// Records `context` as announced to `key`.
    ///
    /// - Returns: whether that was news, i.e. whether the caller should add
    ///   the system line. One step under the lock because the check and the
    ///   write have to be atomic.
    func markAnnounced(_ context: AgentRunner.WorkspaceContext, to key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard announced[key] != context else { return false }
        announced[key] = context
        return true
    }
}
