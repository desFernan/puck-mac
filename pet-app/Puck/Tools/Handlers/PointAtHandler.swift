//
//  PointAtHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Delegates a MoveTo+Point command to the F3 FSM (tool execution = pet action, a special case)
//
//  protocol section 4: point_at is "펫이 좌표로 이동해 가리킴" and returns
//  "Point 시작 시점에". The handler owns neither the walking nor the pointing
//  timer — it hands the target to whoever drives the FSM and replies once
//  that reports the pet has actually started pointing.
//

import CoreGraphics
import Foundation

/// How PointAtHandler asks the FSM to carry out a point_at. Implemented at
/// bootstrap, where the character controller and pointing timer both live.
/// `@MainActor`: the only implementor is the app delegate, which drives the
/// character, and pointing moves it.
@MainActor
protocol PetPointingCoordinating: AnyObject {
    /// Walks the pet to `frame` and starts pointing at it.
    /// - Parameter holdSeconds: how long to keep pointing once it starts.
    ///   nil means PointingController's own default (8s), which is what every
    ///   caller before the code tour wanted -- "point once and go back to
    ///   idle". A tour stop passes a longer hold because the model is still
    ///   explaining while the pet stands there.
    /// - Parameter onPointingStarted: called when Point actually begins.
    func pointAt(frame: CGRect, holdSeconds: TimeInterval?, onPointingStarted: @escaping () -> Void)

    /// Abandons the in-flight point_at (tool_cancel or ToolExecutor's
    /// timeout) -- without this the pet kept walking/pointing on the
    /// caller's behalf after cancellation (found via review).
    func cancelPointing()
}

final class PointAtHandler: ToolHandler {
    let toolName = "point_at"
    private let coordinator: PetPointingCoordinating

    /// The dispatch the pet is currently walking/pointing for. There is one
    /// pet, so a second point_at replaces the first rather than running
    /// beside it -- but a *cancel* still has to name which call it is for, or
    /// the 30s timeout of a superseded call stops the pointing its replacement
    /// is doing. Guarded: `execute` runs on the caller's queue and `cancel`
    /// arrives from ToolExecutor's.
    private let stateQueue = DispatchQueue(label: "Puck.PointAtHandler.state")
    private var activeID: String?

    init(coordinator: PetPointingCoordinating) {
        self.coordinator = coordinator
    }

    func execute(id: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let frame = args.extractFrame() else {
            completion(.failure(.executionFailed("point_at requires a frame {x,y,width,height}")))
            return
        }

        stateQueue.sync { activeID = id }
        // Onto the main actor, because this is not always already there: an
        // MCP call comes off the loopback server's queue, and the coordinator
        // is the app delegate -- it moves the character AppKit is drawing.
        // The hop was missing rather than unnecessary.
        Task { @MainActor [coordinator] in
            coordinator.pointAt(frame: frame, holdSeconds: Self.holdSeconds(from: args)) { [weak self] in
                self?.stateQueue.sync { if self?.activeID == id { self?.activeID = nil } }
                completion(.success(nil))
            }
        }
    }

    /// `hold_seconds`, the optional argument a code tour uses to keep the pet
    /// pointing until its next stop. Absent, zero-or-negative and non-finite
    /// all mean "use the default" rather than failing the call: the pointing
    /// is the useful part, and refusing it over a malformed hint would lose
    /// that for no gain.
    static func holdSeconds(from args: JSONValue) -> TimeInterval? {
        guard case .object(let fields) = args, case .number(let seconds)? = fields["hold_seconds"] else { return nil }
        guard seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, maximumHoldSeconds)
    }

    /// The backstop for a run that never says it finished: a tour stop is
    /// normally released by the next point_at or by agent_done, and this only
    /// applies when both of those fail to arrive.
    static let maximumHoldSeconds: TimeInterval = 60

    func cancel(id: String) {
        let isCurrent = stateQueue.sync {
            guard activeID == id else { return false }
            activeID = nil
            return true
        }
        guard isCurrent else { return }
        // Same hop, and this one is the reason it matters: ToolExecutor's
        // timeout fires on a global queue, so a point_at that timed out was
        // reaching into the character from off the main thread.
        Task { @MainActor [coordinator] in
            coordinator.cancelPointing()
        }
    }
}
