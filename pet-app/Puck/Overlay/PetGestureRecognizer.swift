//
//  PetGestureRecognizer.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Raw mouse events over the character -> tap or drag.
//
//  ClickThroughController already decides *when* the overlay accepts clicks
//  at all (cursor inside the hitbox); this decides what a press-move-release
//  sequence meant. Kept as a value type with no AppKit dependency so the
//  distinction — which is entirely about thresholds and ordering — is
//  testable without synthesizing NSEvents.
//

import CoreGraphics
import Foundation

enum PetGesture: Equatable {
    /// Pressed and released without meaningfully moving.
    case tapped
    /// Two taps in quick succession, close together -- "petting" the
    /// character (2026-07-29).
    case doubleTapped
    case dragBegan(CGPoint)
    case dragMoved(CGPoint)
    case dragEnded
}

struct PetGestureRecognizer {
    /// How far the cursor may travel while pressed and still count as a click.
    /// A hand shifting a pixel or two shouldn't yank the pet across the screen.
    static let dragThreshold: CGFloat = 4
    /// How close together two taps must land, in both position and time, to
    /// count as a double-tap rather than two unrelated single taps.
    static let doubleTapDistanceThreshold: CGFloat = 20
    static let doubleTapMaxInterval: TimeInterval = 0.4

    private var pressOrigin: CGPoint?
    private var isDragging = false
    private var lastTapTime: TimeInterval?
    private var lastTapPosition: CGPoint?
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    mutating func mouseDown(at point: CGPoint) -> PetGesture? {
        pressOrigin = point
        isDragging = false
        return nil
    }

    mutating func mouseDragged(to point: CGPoint) -> PetGesture? {
        // No press means this belongs to something else that happened to pass
        // under the cursor — not an interaction with the pet.
        guard let origin = pressOrigin else { return nil }

        if isDragging {
            return .dragMoved(point)
        }
        guard hypot(point.x - origin.x, point.y - origin.y) > Self.dragThreshold else {
            return nil
        }
        isDragging = true
        return .dragBegan(point)
    }

    mutating func mouseUp(at point: CGPoint) -> PetGesture? {
        guard pressOrigin != nil else { return nil }
        defer {
            pressOrigin = nil
            isDragging = false
        }
        guard !isDragging else { return .dragEnded }

        let currentTime = now()
        if let lastTapTime, let lastTapPosition,
           currentTime - lastTapTime <= Self.doubleTapMaxInterval,
           hypot(point.x - lastTapPosition.x, point.y - lastTapPosition.y) <= Self.doubleTapDistanceThreshold {
            // Consumed: a third quick tap starts a fresh cycle rather than
            // chaining into a triple-tap.
            self.lastTapTime = nil
            self.lastTapPosition = nil
            return .doubleTapped
        }

        lastTapTime = currentTime
        lastTapPosition = point
        return .tapped
    }
}
