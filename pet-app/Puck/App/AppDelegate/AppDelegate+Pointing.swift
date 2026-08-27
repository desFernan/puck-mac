//
//  AppDelegate+Pointing.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Walks the pet to a target and holds a point gesture on it, driven by
//  point_at / tool_cancel.
//

import CoreGraphics
import Foundation

extension AppDelegate {
    // MARK: - Pointing (F10/F11)

    /// point_at: walk to the target, then point at it. The tool only learns
    /// the pet arrived when Point is actually entered, which is what protocol
    /// section 4 promises the agent.
    ///
    /// `frame` is in the global Quartz space the tools and the window list
    /// speak. It is handed to ClickDetector as-is (it compares against the
    /// cursor in that same space) and rebased for the walk, which happens in
    /// the pet's.
    func pointAt(frame: CGRect, holdSeconds: TimeInterval? = nil, onPointingStarted: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let controller = self.characterController else {
                onPointingStarted() // nothing can point; don't strand the caller
                return
            }

            // A still-pending point_at (pet hasn't arrived yet) redirects the
            // walk, same as MoveTo's target being overwritten -- but its
            // caller was still waiting on onPointingStarted, which would
            // otherwise be silently dropped and hang until ToolExecutor's
            // 15s timeout instead of getting a reply now.
            if let superseded = self.pendingPointTracker.replace(frame: frame, holdSeconds: holdSeconds, onStarted: onPointingStarted) {
                superseded()
            }

            // A wander half-walked is not something to come back to after
            // pointing at something the user asked about.
            self.cancelWander()

            // A hold this long means a guided tour is running (show_code),
            // and the pet's normal 90 px/s takes ~17s to cross a wide display
            // -- most of the first stop would be spent watching it walk.
            // Sped up rather than teleported: the pet going there is the
            // feature, so removing the walk removes it.
            if holdSeconds != nil {
                // A tour points at the editor pane, which is below the tank --
                // out of reach from inside the glass.
                self.petHomeDecider.forceDesktop()
                self.characterController?.walkSpeed = MovementSolver.walkSpeed
                    * self.settingsStore.walkSpeedMultiplier
                    * Self.tourWalkSpeedMultiplier
            }

            // Stand beside the target rather than on top of it, so the
            // character isn't covering what it is trying to show.
            let standOffset: CGFloat = 60
            self.states.moveTo.target = self.overlayLocalPoint(
                fromQuartz: CGPoint(x: frame.midX - standOffset, y: frame.maxY)
            )
            self.states.moveTo.nextState = .point
            controller.transition(to: .moveTo)
        }
    }

    /// tool_cancel or ToolExecutor's 15s timeout for an in-flight point_at.
    /// Clears the tracked entry so a pet that arrives after cancellation
    /// doesn't still fire onPointingStarted for a call the caller was
    /// already told was cancelled (found via review).
    func cancelPointing() {
        DispatchQueue.main.async { [weak self] in
            self?.pendingPointTracker.clearPending()
        }
    }

    /// Called by PointState once the pet is in place and the point clip is up.
    func beginPointingTimer() {
        guard let (frame, holdSeconds, onStarted) = pendingPointTracker.consumeIfPending() else { return }

        pointingController.onPointingReleased = { [weak self] in
            self?.characterController?.transition(to: .idle)
        }
        pointingController.beginPointing(
            targetFrame: frame,
            timeout: holdSeconds ?? PointingController.defaultTimeout
        )
        onStarted()
    }

    /// The run that asked for the pointing is over, so there is nothing left
    /// to point at -- without this a tour's last stop, which asked to be held
    /// until the next instruction, would stand there for its full backstop
    /// (PointAtHandler.maximumHoldSeconds) after the pet had already said its
    /// piece.
    ///
    /// Only the holding half: a point_at still walking to its target keeps
    /// going, because its caller has not been replied to yet and dropping it
    /// here would hang that dispatch until ToolExecutor's timeout.
    func releasePointingForFinishedRun() {
        pointingController.releaseIfActive()
        restoreWalkSpeed()
    }

    /// Back to whatever Settings' movement slider says. Called on agent_done
    /// rather than at the end of each stop: a tour is several point_at calls
    /// and the walk between them should stay quick throughout.
    func restoreWalkSpeed() {
        characterController?.walkSpeed = MovementSolver.walkSpeed * settingsStore.walkSpeedMultiplier
    }

    /// Fast enough that the one walk a tour actually makes lands in a few
    /// seconds, slow enough to still read as walking.
    static let tourWalkSpeedMultiplier: CGFloat = 3
}
