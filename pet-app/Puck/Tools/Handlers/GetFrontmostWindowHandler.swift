//
//  GetFrontmostWindowHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Returns frontmost window info (via F4)
//

import AppKit

final class GetFrontmostWindowHandler: ToolHandler {
    let toolName = "get_frontmost_window"
    private let watcher: WindowListWatcher

    /// `watcher` is shared with the rest of the app (constructed once at app
    /// bootstrap) so this handler always sees the latest polled window list.
    init(watcher: WindowListWatcher) {
        self.watcher = watcher
    }

    /// Hops to the main actor before reading the window list.
    ///
    /// Tools run on ToolExecutor's own queue, and the list is rebuilt by a
    /// timer on the main run loop -- so this used to read an array while
    /// another thread was replacing it. Nothing had said so out loud until
    /// the watcher was given an isolation to state.
    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        Task { @MainActor [watcher] in
            Self.answer(from: watcher, completion: completion)
        }
    }

    @MainActor
    private static func answer(
        from watcher: WindowListWatcher,
        completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void
    ) {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            completion(.failure(.executionFailed("no frontmost application")))
            return
        }

        // Asked for now rather than read from the last poll: the rate drops
        // while the pet rests, and this is the one caller for which a list
        // half a second old is a wrong answer rather than a late one.
        guard let window = watcher.windowsNow().first(where: { $0.ownerPID == frontmostPID }) else {
            completion(.success(.null))
            return
        }

        completion(
            .success(
                .object([
                    "owner_name": window.ownerName.map(JSONValue.string) ?? .null,
                    "title": window.title.map(JSONValue.string) ?? .null,
                    "frame": .object([
                        "x": .number(window.frame.origin.x),
                        "y": .number(window.frame.origin.y),
                        "width": .number(window.frame.width),
                        "height": .number(window.frame.height),
                    ]),
                ])
            )
        )
    }
}
