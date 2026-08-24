//
//  PointingController.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  point_at: MoveTo(offset)+facing+Point loop, released after 8s or on click detection
//
//  Scope note: this owns the release timing (8s timeout vs. click-detected)
//  once the FSM has already arrived at the target and entered Point. The
//  MoveTo(offset)+facing approach to *reach* the target is F3's job and
//  isn't wired up yet (Movement/States/MoveToState.swift still has no real
//  movement math — see its TODO), so beginPointing() assumes arrival already
//  happened. tool_result(ok) at "Point start" (protocol section 4) is the
//  caller's (F11 PointAtHandler) responsibility, triggered by onPointingStarted.

import CoreGraphics
import Foundation

final class PointingController {
    static let defaultTimeout: TimeInterval = 8

    /// Called as soon as pointing starts — F11's PointAtHandler should reply
    /// tool_result(ok) here (protocol section 4: "Point 시작 시점에 tool_result(ok) 반환").
    var onPointingStarted: (() -> Void)?
    /// Called once pointing ends (timeout or click detected) — the caller
    /// transitions the FSM back to Idle.
    var onPointingReleased: (() -> Void)?

    private let clickDetector: ClickDetectorProviding
    private var elapsed: TimeInterval = 0
    private var timeout: TimeInterval = PointingController.defaultTimeout
    private var isActive = false

    init(clickDetector: ClickDetectorProviding = ClickDetector()) {
        self.clickDetector = clickDetector
    }

    func beginPointing(targetFrame: CGRect, timeout: TimeInterval = PointingController.defaultTimeout) {
        self.timeout = timeout
        elapsed = 0
        isActive = true

        clickDetector.onClickInsideTarget = { [weak self] in self?.release() }
        clickDetector.startMonitoring(targetFrame: targetFrame)
        onPointingStarted?()
    }

    /// Call every frame while Point is the active FSM state.
    func tick(dt: TimeInterval) {
        guard isActive else { return }
        elapsed += dt
        if elapsed >= timeout {
            release()
        }
    }

    /// Ends the hold early. A no-op when nothing is being pointed at, so the
    /// caller (agent_done, which arrives whether or not the run pointed at
    /// anything) does not have to know.
    func releaseIfActive() {
        release()
    }

    private func release() {
        guard isActive else { return }
        isActive = false
        clickDetector.stopMonitoring()
        onPointingReleased?()
    }
}
