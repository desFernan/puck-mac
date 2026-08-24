//
//  ReactStateTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  "임의 | 캐릭터 클릭 | ReactClick → Idle" and "임의 | 캐릭터 드래그/드롭 |
//  ReactDrag(커서 추종) → Fall" (plan/02_pet-app.md section 3).
//

import XCTest
@testable import Puck

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class ReactClickStateTests: XCTestCase {
    func test_returnsToIdleAfterTheReactionPlays() {
        let world = TestStateWorld()
        let state = ReactClickState()
        state.enter()

        world.run(state, seconds: 0.05)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "the reaction clip needs a moment to read")

        world.run(state, seconds: 2)
        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    /// Clicking the pet repeatedly should replay the reaction, not queue up a
    /// backlog of transitions from the first one.
    func test_reentryRestartsTheTimer() {
        let world = TestStateWorld()
        let state = ReactClickState()

        state.enter()
        world.run(state, seconds: 2)
        state.enter()
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.requestedTransitions.count, 1, "the second reaction has not finished yet")
    }
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class PettingStateTests: XCTestCase {
    func test_returnsToIdleAfterTheReactionPlays() {
        let world = TestStateWorld()
        let state = PettingState()
        state.enter()

        world.run(state, seconds: 0.1)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "the wiggle needs a moment to read")

        world.run(state, seconds: 2)
        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    /// Petting the pet again while it's still reacting should replay the
    /// reaction, not queue up a backlog of transitions from the first one.
    func test_reentryRestartsTheTimer() {
        let world = TestStateWorld()
        let state = PettingState()

        state.enter()
        world.run(state, seconds: 2)
        state.enter()
        world.run(state, seconds: 0.1)

        XCTAssertEqual(world.requestedTransitions.count, 1, "the second reaction has not finished yet")
    }
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class ReactDragStateTests: XCTestCase {
    /// One frame to register the grab, then the cursor moves. Mirrors how
    /// AppDelegate feeds .dragBegan and then .dragMoved.
    private func grab(_ state: ReactDragState, at point: CGPoint, in world: TestStateWorld) {
        state.cursorPosition = point
        world.run(state, seconds: 1.0 / 60)
    }

    /// Dragging a window keeps the grabbed point under the cursor; grabbing
    /// the pet must not re-center it on the cursor either, the same way
    /// dragging any ordinary window works.
    func test_grabbingDoesNotMoveThePet() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 400))
        let state = ReactDragState()
        state.enter()

        // Grabbed 30px to the left of and 20px above the pet's origin.
        grab(state, at: CGPoint(x: 470, y: 380), in: world)

        XCTAssertEqual(world.body.position, CGPoint(x: 500, y: 400))
    }

    func test_followsTheCursor_keepingTheGrabOffset() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 400))
        let state = ReactDragState()
        state.enter()
        grab(state, at: CGPoint(x: 470, y: 380), in: world)

        state.cursorPosition = CGPoint(x: 570, y: 430) // cursor moved +100, +50
        world.run(state, seconds: 1)

        // The pet moved by the same delta, offset intact.
        XCTAssertEqual(world.body.position.x, 600, accuracy: 0.5)
        XCTAssertEqual(world.body.position.y, 450, accuracy: 0.5)
    }

    /// The pet is carried, not moving under its own power, so it has no speed of its own to
    /// lag behind at: it is wherever the cursor is on the very next frame,
    /// however far the cursor jumped.
    func test_tracksTheCursorWithinASingleFrame_howeverFarItMoved() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)

        state.cursorPosition = CGPoint(x: 20, y: 10) // an ordinary drag
        world.run(state, seconds: 1.0 / 60) // exactly one frame
        XCTAssertEqual(world.body.position, CGPoint(x: 20, y: 10))

        state.cursorPosition = CGPoint(x: 2000, y: 10) // a hard flick
        world.run(state, seconds: 1.0 / 60)
        XCTAssertEqual(world.body.position, CGPoint(x: 2000, y: 10), "stays stuck to the cursor")
    }

    func test_releasingDropsThePet() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)
        state.cursorPosition = CGPoint(x: 300, y: 150)
        world.run(state, seconds: 0.05)

        state.release()
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    /// The pet must stay where it was dropped rather than snapping back to
    /// wherever the cursor wandered afterwards.
    func test_afterRelease_stopsFollowingTheCursor() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)
        state.cursorPosition = CGPoint(x: 300, y: 150)
        world.run(state, seconds: 1)
        let droppedPosition = world.body.position

        state.release()
        world.run(state, seconds: 0.05)

        state.cursorPosition = CGPoint(x: 900, y: 900)
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.body.position, droppedPosition)
    }

    // MARK: - Throwing

    /// Drags the cursor at a steady `speed` px/sec to the right for `seconds`.
    private func swipe(_ state: ReactDragState, speed: CGFloat, seconds: TimeInterval, in world: TestStateWorld) {
        let frame = 1.0 / 60
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            let cursor = state.cursorPosition ?? .zero
            state.cursorPosition = CGPoint(x: cursor.x + speed * CGFloat(frame), y: cursor.y)
            world.run(state, seconds: frame)
            elapsed += frame
        }
    }

    func test_releasingMidSwipeThrowsThePet() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)

        swipe(state, speed: 800, seconds: 0.3, in: world)
        state.release()
        world.run(state, seconds: 1.0 / 60)

        XCTAssertEqual(world.body.launchVelocity.x, 800, accuracy: 80, "thrown at the speed it was swiped")
        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    /// Letting go of a stationary cursor is a drop, not a throw — the pet must
    /// fall straight down the way it always did.
    func test_releasingAStillCursorThrowsNothing() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)

        swipe(state, speed: 800, seconds: 0.3, in: world)
        world.run(state, seconds: 0.5) // held still before letting go
        state.release()
        world.run(state, seconds: 1.0 / 60)

        // The smoothing decays rather than hard-resetting, so a couple of px/s
        // survives half a second of stillness — under 1/300th of the swipe,
        // and less than a tenth of a pixel of drift over the whole fall.
        XCTAssertEqual(world.body.launchVelocity.x, 0, accuracy: 5)
    }

    func test_aViolentFlickIsCappedAtMaxThrowSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)

        swipe(state, speed: 12_000, seconds: 0.3, in: world)
        state.release()
        world.run(state, seconds: 1.0 / 60)

        XCTAssertEqual(world.body.launchVelocity.x, MovementSolver.maxThrowSpeed, accuracy: 0.001)
    }

    /// A new grab must not inherit the previous throw's speed.
    func test_velocityResetsOnReentry() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: .zero, in: world)
        swipe(state, speed: 800, seconds: 0.3, in: world)

        state.enter() // grabbed again
        grab(state, at: world.body.position, in: world)
        state.release()
        world.run(state, seconds: 1.0 / 60)

        XCTAssertEqual(world.body.launchVelocity, .zero)
    }

    func test_facesTheDirectionItIsDraggedIn() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 0))
        let state = ReactDragState()
        state.enter()
        grab(state, at: CGPoint(x: 500, y: 0), in: world)

        state.cursorPosition = CGPoint(x: 100, y: 0)
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.avatar.facings.last, .left)
    }
}

/// Stroking the pet's head holds the reaction open, then hands off to the
/// twirl for a while.
/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class PettingStrokeTests: XCTestCase {
    func test_strokingHoldsTheReactionOpenIndefinitely() {
        let world = TestStateWorld()
        let state = PettingState()
        state.enter()
        state.beginStroking()

        world.run(state, seconds: PettingState.duration * 10)

        XCTAssertTrue(world.requestedTransitions.isEmpty, "petting lasts as long as the user keeps going")
    }

    func test_endingAStrokeTwirls() {
        let world = TestStateWorld()
        let state = PettingState()
        state.enter()
        state.beginStroking()
        world.run(state, seconds: 1)

        state.endStroking()
        world.run(state, seconds: 0.05)

        XCTAssertEqual(world.requestedTransitions, [.spin])
    }

    /// The double-tap reaction is unchanged — it times out to idle, and earns
    /// no twirl.
    func test_aDoubleTapReactionStillEndsAtIdle() {
        let world = TestStateWorld()
        let state = PettingState()
        state.enter()

        world.run(state, seconds: PettingState.duration + 0.1)

        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    /// enter() clears the stroking flag, so a re-entry can't leave the pet
    /// stuck being petted forever by a stroke that already finished.
    func test_reentryClearsStroking() {
        let world = TestStateWorld()
        let state = PettingState()
        state.enter()
        state.beginStroking()

        state.enter()
        world.run(state, seconds: PettingState.duration + 0.1)

        XCTAssertEqual(world.requestedTransitions, [.idle])
    }
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class SpinStateTests: XCTestCase {
    func test_returnsToIdleAfterTheTwirl() {
        let world = TestStateWorld()
        let state = SpinState()
        state.enter()

        world.run(state, seconds: SpinState.duration - 0.1)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "still spinning")

        world.run(state, seconds: 0.2)
        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    func test_spinningDoesNotMoveThePet() {
        let world = TestStateWorld(position: CGPoint(x: 300, y: 400))
        let state = SpinState()
        state.enter()

        world.run(state, seconds: SpinState.duration)

        XCTAssertEqual(world.body.position, CGPoint(x: 300, y: 400), "the twirl is a rendering effect only")
    }
}

/// The flip itself. Turning about the vertical axis, not in the image plane.
/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class SpinBouncePresetTests: XCTestCase {
    private let preset = BouncePreset.spin

    func test_spinClipUsesTheSpinPreset() {
        XCTAssertEqual(BouncePreset.preset(for: "spin"), .spin)
    }

    /// An in-plane rotation tips the pet over sideways, which reads as
    /// falling. The flip has to be pure horizontal scale.
    func test_neverRotatesInThePlane() {
        for step in 0...100 {
            let transform = preset.transform(elapsed: SpinState.duration * Double(step) / 100, intensity: 1)
            XCTAssertEqual(transform.rotation, 0, "tipped over at step \(step)")
        }
    }

    func test_startsAndEndsFacingForward() {
        XCTAssertEqual(preset.transform(elapsed: 0, intensity: 1).scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(
            preset.transform(elapsed: SpinState.duration, intensity: 1).scaleX,
            1,
            accuracy: 0.0001,
            "a fractional last turn would leave the pet stuck side-on"
        )
    }

    /// Edge-on at each quarter turn, and fully reversed at each half turn --
    /// that sweep through zero width is what makes it read as flipping over.
    func test_passesThroughEdgeOnAndFullyReversed() {
        var sawEdgeOn = false
        var sawReversed = false
        for step in 0...400 {
            let scaleX = preset.transform(elapsed: SpinState.duration * Double(step) / 400, intensity: 1).scaleX
            if abs(scaleX) < 0.05 { sawEdgeOn = true }
            if scaleX < -0.95 { sawReversed = true }
        }

        XCTAssertTrue(sawEdgeOn, "never turned edge-on")
        XCTAssertTrue(sawReversed, "never showed its back")
    }

    func test_flipsSeveralTimes() {
        var crossings = 0
        var previous = preset.transform(elapsed: 0, intensity: 1).scaleX
        for step in 1...1000 {
            let scaleX = preset.transform(elapsed: SpinState.duration * Double(step) / 1000, intensity: 1).scaleX
            if (previous >= 0) != (scaleX >= 0) { crossings += 1 }
            previous = scaleX
        }

        // Three full turns = six passes through edge-on.
        XCTAssertEqual(crossings, 6)
    }

    /// Fast at first, coasting to a stop -- not a constant rate.
    func test_decelerates() {
        func flips(from: Double, to: Double) -> Int {
            var crossings = 0
            var previous = preset.transform(elapsed: SpinState.duration * from, intensity: 1).scaleX
            for step in 1...500 {
                let t = from + (to - from) * Double(step) / 500
                let scaleX = preset.transform(elapsed: SpinState.duration * t, intensity: 1).scaleX
                if (previous >= 0) != (scaleX >= 0) { crossings += 1 }
                previous = scaleX
            }
            return crossings
        }

        XCTAssertGreaterThan(flips(from: 0, to: 0.25), flips(from: 0.75, to: 1), "slows down toward the end")
    }

    func test_zeroIntensityIsCompletelyStill() {
        XCTAssertEqual(preset.transform(elapsed: 0.5, intensity: 0), .identity)
    }
}

/// The rainbow wash over the flips, one hue in order per flip.
/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class SpinRainbowTests: XCTestCase {
    private let preset = BouncePreset.spin

    func test_theHuesAreARainbowInOrder() {
        // Red through violet: hue increases monotonically around the wheel.
        XCTAssertEqual(BouncePreset.rainbowHues, BouncePreset.rainbowHues.sorted())
        XCTAssertEqual(BouncePreset.rainbowHues.count, 7)
        XCTAssertEqual(BouncePreset.rainbowHues.first, 0, "starts at red")
    }

    func test_eachHalfTurnTakesTheNextColour() {
        for halfTurn in 0..<BouncePreset.rainbowHues.count {
            XCTAssertEqual(BouncePreset.rainbowHue(halfTurn: halfTurn), BouncePreset.rainbowHues[halfTurn])
        }
    }

    func test_theRainbowWrapsRatherThanRunningOut() {
        XCTAssertEqual(BouncePreset.rainbowHue(halfTurn: 7), BouncePreset.rainbowHues[0])
        XCTAssertEqual(BouncePreset.rainbowHue(halfTurn: 9), BouncePreset.rainbowHues[2])
    }

    /// The colour must change exactly as the sprite passes edge-on, so it
    /// reads as the other side being a different colour.
    func test_theColourChangesWhileEdgeOn() {
        var changes: [(scaleX: Double, hue: Double?)] = []
        var previous = preset.transform(elapsed: 0, intensity: 1)
        for step in 1...2000 {
            let current = preset.transform(elapsed: SpinState.duration * Double(step) / 2000, intensity: 1)
            if current.tintHue != previous.tintHue {
                changes.append((current.scaleX, current.tintHue))
            }
            previous = current
        }

        XCTAssertFalse(changes.isEmpty, "the tint never changed")
        for change in changes {
            XCTAssertLessThan(abs(change.scaleX), 0.05, "recoloured while facing the viewer")
        }
    }

    func test_theSpinIsTintedThroughout() {
        for step in 0...100 {
            let transform = preset.transform(elapsed: SpinState.duration * Double(step) / 100, intensity: 1)
            XCTAssertNotNil(transform.tintHue, "untinted at step \(step)")
        }
    }

    /// Nothing else may tint — the pet is its own colours the rest of the time.
    func test_noOtherPresetTints() {
        for other in [BouncePreset.none, .idle, .walk, .land, .pop, .kick, .wiggle, .climb] {
            for step in 0...20 {
                XCTAssertNil(
                    other.transform(elapsed: Double(step) * 0.05, intensity: 1).tintHue,
                    "\(other) tinted the pet"
                )
            }
        }
    }
}
