//
//  BallControllerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Glue between BallPhysics and its CALayer -- spawn/tick/kick/reparent.
//

import XCTest
import QuartzCore
@testable import Puck

final class BallControllerTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func test_spawn_showsTheLayerAtTheGivenPosition() {
        let parent = CALayer()
        let controller = BallController(parent: parent)

        controller.spawn(at: CGPoint(x: 200, y: 0))

        XCTAssertFalse(controller.layer.isHidden)
        XCTAssertEqual(controller.layer.position, CGPoint(x: 200, y: 0))
        XCTAssertTrue(controller.isActive)
    }

    func test_beforeSpawn_isNotActive() {
        let controller = BallController(parent: CALayer())
        XCTAssertFalse(controller.isActive)
    }

    func test_tick_movesTheLayerAsTheBallFalls() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 0))

        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertGreaterThan(controller.layer.position.y, 0)
    }

    func test_tick_firesOnLanded_exactlyOnceWhenItReachesTheGround() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        var landedPositions: [CGPoint] = []
        controller.onLanded = { landedPositions.append($0) }

        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // lands this frame
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // resting, must not refire

        XCTAssertEqual(landedPositions.count, 1)
    }

    func test_kick_whileResting_launchesIt() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // now resting

        controller.kick(direction: .right)
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertGreaterThan(controller.layer.position.x, 200, "kicked right should move it right")
    }

    func test_kick_whileNotYetResting_isANoOp() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 0)) // still falling

        controller.kick(direction: .right)

        XCTAssertTrue(controller.isActive) // unaffected -- no crash, no state change
    }

    // MARK: - juggle() (F12 juggle-before-kick variety, 2026-07-29)

    func test_juggle_whileResting_popsItUpward() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // now resting
        let restingY = controller.layer.position.y

        controller.juggle()
        controller.tick(dt: 0.05, landingY: 500, roamableArea: roamableArea)

        XCTAssertLessThan(controller.layer.position.y, restingY, "should have popped upward")
    }

    func test_juggle_thenFallsBackAndRests() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // now resting

        controller.juggle()
        for _ in 0..<30 { // enough time for a small pop to arc back down
            controller.tick(dt: 0.05, landingY: 500, roamableArea: roamableArea)
        }

        // Back on the surface -- measured to the artwork's bottom edge, not to
        // the layer's centre, which would bury the toy in the floor.
        XCTAssertEqual(controller.layer.position.y + controller.visualBounds.maxY, 500, accuracy: 0.5)
    }

    /// Nothing expires the toy any more, so the only route to `.gone` is
    /// having no surface at all beneath it.
    func test_tick_hidesTheLayerAndDeactivates_onceGone() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // resting
        controller.kick(direction: .right)

        for _ in 0..<40 {
            // No landing surface anywhere below: the toy falls away and is
            // eventually cleaned up.
            controller.tick(dt: 0.1, landingY: 99_999, roamableArea: roamableArea)
        }

        XCTAssertTrue(controller.layer.isHidden)
        XCTAssertFalse(controller.isActive)
    }

    /// The toy is permanent --
    /// a kick has to end with it back in play, not gone.
    func test_aKickedToyStaysOnScreenAndComesBackToRest() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea)
        controller.kick(direction: .right)

        for _ in 0..<600 {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertTrue(controller.isActive, "the toy disappeared")
        XCTAssertEqual(controller.state?.phase, .resting)
    }

    /// Throwing again moves the toy instead of doing nothing -- otherwise the
    /// menu item is dead forever after the first throw.
    func test_spawn_whileAlreadyInPlay_movesTheToy() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 0.5, landingY: 500, roamableArea: roamableArea)

        controller.spawn(at: CGPoint(x: 800, y: 50))

        XCTAssertEqual(controller.state?.position, CGPoint(x: 800, y: 50))
        XCTAssertEqual(controller.state?.phase, .falling, "dropped again from the new spot")
    }

    func test_reparent_movesTheLayerToTheNewParent() {
        let oldParent = CALayer()
        let controller = BallController(parent: oldParent)
        XCTAssertTrue(oldParent.sublayers?.contains(controller.layer) ?? false)

        let newParent = CALayer()
        controller.reparent(to: newParent)

        XCTAssertFalse(oldParent.sublayers?.contains(controller.layer) ?? false)
        XCTAssertTrue(newParent.sublayers?.contains(controller.layer) ?? false)
    }
}

/// Resting the toy on a surface by its artwork rather than by its layer.
final class BallToyVisualBoundsTests: XCTestCase {
    private func makeController() -> BallController {
        BallController(parent: CALayer())
    }

    /// Without artwork the fallback is a drawn circle, which fills its box.
    func test_theDrawnCircleFallbackFillsItsBox() {
        let controller = makeController()

        // Whichever path ran, the bounds must be centred on the position and
        // no larger than the layer.
        XCTAssertEqual(controller.visualBounds.midX, 0, accuracy: 3, "not centred horizontally")
        XCTAssertLessThanOrEqual(controller.visualBounds.width, controller.layer.bounds.width + 0.01)
        XCTAssertLessThanOrEqual(controller.visualBounds.height, controller.layer.bounds.height + 0.01)
    }

    /// The artwork's bottom edge is what has to meet the surface. Resting the
    /// layer's centre there buries half the toy; resting its bottom edge
    /// leaves it hovering on the transparent margin.
    func test_theToyRestsOnItsArtworkNotItsCentre() {
        let controller = makeController()
        let floor: CGFloat = 400

        controller.spawn(at: CGPoint(x: 100, y: 0))
        // Long enough to have certainly landed.
        for _ in 0..<300 {
            controller.tick(dt: 1.0 / 60, landingY: floor, roamableArea: CGRect(x: 0, y: 0, width: 800, height: 800))
        }

        let position = try? XCTUnwrap(controller.state?.position)
        let restingY = try? XCTUnwrap(position?.y)
        XCTAssertEqual(controller.state?.phase, .resting)

        // Bottom of the artwork == the surface.
        XCTAssertEqual((restingY ?? 0) + controller.visualBounds.maxY, floor, accuracy: 0.01)
        XCTAssertLessThan(restingY ?? 0, floor, "the toy's centre must sit above the surface it rests on")
    }

    /// A regression guard on the specific mistake: the centre landing exactly
    /// on the surface, which is what happens if visualBounds is ignored.
    func test_theToyDoesNotSinkIntoTheSurface() {
        let controller = makeController()
        let floor: CGFloat = 400
        controller.spawn(at: CGPoint(x: 100, y: 0))
        for _ in 0..<300 {
            controller.tick(dt: 1.0 / 60, landingY: floor, roamableArea: CGRect(x: 0, y: 0, width: 800, height: 800))
        }

        let sunk = (controller.state?.position.y ?? 0) - floor
        XCTAssertLessThanOrEqual(sunk, 0, "the toy is \(sunk)pt into the floor")
    }
}

/// Picking the toy up with the cursor, the same way the pet itself can be
/// picked up.
final class BallToyGrabTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func restingToy() -> BallController {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: roamableArea)
        XCTAssertEqual(controller.state?.phase, .resting)
        return controller
    }

    func test_grabbingSuspendsPhysics() {
        let controller = restingToy()
        controller.grab()
        let held = controller.state?.position

        // Plenty of frames with a surface far below: gravity must not act.
        for _ in 0..<120 {
            controller.tick(dt: 1.0 / 60, landingY: 5000, roamableArea: roamableArea)
        }

        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(controller.state?.position, held, "the toy moved while it was being held")
    }

    func test_movingCarriesTheToyAndItsLayer() {
        let controller = restingToy()
        controller.grab()

        controller.move(to: CGPoint(x: 700, y: 120))

        XCTAssertEqual(controller.state?.position, CGPoint(x: 700, y: 120))
        XCTAssertEqual(controller.layer.position, CGPoint(x: 700, y: 120), "the drawing has to follow too")
    }

    /// Only a held toy may be carried -- otherwise a stray call could
    /// teleport one mid-flight.
    func test_movingAToyThatIsNotHeldDoesNothing() {
        let controller = restingToy()
        let before = controller.state?.position

        controller.move(to: CGPoint(x: 700, y: 120))

        XCTAssertEqual(controller.state?.position, before)
    }

    func test_releasingDropsItFromWhereItWasLetGo() {
        let controller = restingToy()
        controller.grab()
        controller.move(to: CGPoint(x: 700, y: 50))

        controller.release()
        XCTAssertEqual(controller.state?.phase, .falling)
        XCTAssertFalse(controller.isHeld)

        for _ in 0..<600 where controller.state?.phase == .falling {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertEqual(controller.state?.phase, .resting, "it should land again")
        XCTAssertEqual(
            (controller.state?.position.y ?? 0) + controller.visualBounds.maxY,
            500,
            accuracy: 0.01,
            "resting on the surface by its artwork, same as any other landing"
        )
    }

    /// Being carried must not leave it stuck in mid-air if it's never
    /// released -- but equally, holding it over the floor and letting go has
    /// to land it rather than leaving it floating.
    func test_aHeldToyIsNotAffectedByScreenBounds() {
        let controller = restingToy()
        controller.grab()

        // Carried well outside the roamable area, as a cursor can do.
        controller.move(to: CGPoint(x: -300, y: -200))
        controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(controller.state?.position, CGPoint(x: -300, y: -200), "the hand outranks the walls")
    }
}

/// Lifting the toy onto the pet's head to start the heading loop.
final class BallToyLiftTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func restingToy() -> BallController {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: roamableArea)
        return controller
    }

    func test_liftPlacesTheToyOnTheHeadAndSendsItUp() {
        let controller = restingToy()
        let headTop: CGFloat = 300

        controller.lift(overX: 640, headTop: headTop)

        XCTAssertEqual(controller.state?.position.x, 640, "directly over the pet")
        XCTAssertEqual(
            (controller.state?.position.y ?? 0) + controller.visualBounds.maxY,
            headTop,
            accuracy: 0.01,
            "sitting on the head by its artwork, like any other surface"
        )
        XCTAssertLessThan(controller.state?.verticalVelocity ?? 0, 0, "travelling upward")
        XCTAssertEqual(controller.state?.horizontalVelocity, 0, "straight up, so it comes back down on the head")
        XCTAssertEqual(controller.state?.phase, .falling)
    }

    /// It arcs up and comes back to where it started -- that return is what
    /// the head-collision path then turns into the next bounce.
    func test_aLiftedToyComesBackDownToTheHead() {
        let controller = restingToy()
        let headTop: CGFloat = 300
        controller.lift(overX: 640, headTop: headTop)

        var rose = false
        for _ in 0..<600 {
            controller.tick(dt: 1.0 / 60, landingY: headTop, roamableArea: roamableArea)
            if (controller.state?.verticalVelocity ?? 0) < 0 { rose = true }
            if controller.state?.phase == .resting { break }
        }

        XCTAssertTrue(rose, "never went up")
        XCTAssertEqual(controller.state?.phase, .resting, "never came back down onto the head")
        XCTAssertEqual(controller.state?.position.x, 640, "drifted sideways off the head")
    }

    /// A toy in the user's hand must not be yanked onto the pet's head.
    func test_liftIgnoresAHeldToy() {
        let controller = restingToy()
        controller.grab()
        let held = controller.state?.position

        controller.lift(overX: 640, headTop: 300)

        XCTAssertEqual(controller.state?.position, held)
        XCTAssertTrue(controller.isHeld)
    }
}

extension BallToyLiftTests {
    /// The throw has to clear the pet's head by a visible margin, not just
    /// hop off it.
    func test_theThrowGoesWellAboveTheHead() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: CGRect(x: 0, y: 0, width: 1000, height: 600))

        let headTop: CGFloat = 400
        controller.lift(overX: 500, headTop: headTop)

        var highest = CGFloat.greatestFiniteMagnitude
        for _ in 0..<600 {
            // No ceiling in the way, so the arc is the arc.
            controller.tick(dt: 1.0 / 60, landingY: headTop, roamableArea: CGRect(x: 0, y: 0, width: 1000, height: 10_000))
            highest = min(highest, (controller.state?.position.y ?? 0) + controller.visualBounds.maxY)
            if controller.state?.phase == .resting { break }
        }

        let clearance = headTop - highest
        XCTAssertGreaterThan(clearance, 100, "only cleared the head by \(clearance)pt")
        XCTAssertEqual(controller.state?.phase, .resting, "and it still comes back down")
    }
}

/// Resizing the toy.
final class BallToyScaleTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func test_scalingResizesTheLayer() {
        let controller = BallController(parent: CALayer())
        let base = controller.layer.bounds.width

        controller.updateScale(2)

        XCTAssertEqual(controller.layer.bounds.width, base * 2, accuracy: 0.01)
    }

    /// Repeated slider drags must recompute from the built-in size, not
    /// multiply the current one -- the trap the pet's own scaling documents.
    func test_scalingIsNotCumulative() {
        let controller = BallController(parent: CALayer())
        let base = controller.layer.bounds.width

        controller.updateScale(2)
        controller.updateScale(2)
        controller.updateScale(1.5)

        XCTAssertEqual(controller.layer.bounds.width, base * 1.5, accuracy: 0.01)
    }

    /// Everything that keeps the toy out of the floor and off the walls is
    /// measured from its outline, so that has to follow the size.
    func test_theOutlineFollowsTheSize() {
        let controller = BallController(parent: CALayer())
        let base = controller.visualBounds

        controller.updateScale(2)

        XCTAssertEqual(controller.visualBounds.width, base.width * 2, accuracy: 0.01)
        XCTAssertEqual(controller.visualBounds.maxY, base.maxY * 2, accuracy: 0.01)
    }

    func test_scalingCanBeSetAtConstruction() {
        let big = BallController(parent: CALayer(), toy: ToyCatalogue.default, scale: 2)
        let normal = BallController(parent: CALayer())

        XCTAssertEqual(big.layer.bounds.width, normal.layer.bounds.width * 2, accuracy: 0.01)
    }

    /// A toy resting on the floor when it's resized would be left buried in
    /// it (grown) or hovering above it (shrunk), so it drops again.
    func test_resizingARestingToyLetsItSettleAgain() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: roamableArea)
        XCTAssertEqual(controller.state?.phase, .resting)

        controller.updateScale(2)
        XCTAssertEqual(controller.state?.phase, .falling, "should re-settle at its new size")

        for _ in 0..<600 where controller.state?.phase == .falling {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertEqual(
            (controller.state?.position.y ?? 0) + controller.visualBounds.maxY,
            500,
            accuracy: 0.01,
            "the bigger toy must still rest ON the floor"
        )
    }
}

extension BallToyGrabTests {
    /// Throwing the toy, exactly as the pet is thrown.
    func test_releasingWithSpeedThrowsTheToy() {
        let controller = restingToyForThrow()
        controller.grab()

        controller.release(velocity: CGPoint(x: 600, y: -300))

        XCTAssertEqual(controller.state?.phase, .kicked, "a throw needs the sideways physics, not a plain fall")
        XCTAssertEqual(controller.state?.horizontalVelocity, 600)
        XCTAssertEqual(controller.state?.verticalVelocity, -300)
    }

    /// Let go of a still cursor and it's a drop, not a throw -- the same rule
    /// the pet follows.
    func test_releasingWithNoSpeedJustDropsIt() {
        let controller = restingToyForThrow()
        controller.grab()

        controller.release()

        XCTAssertEqual(controller.state?.phase, .falling)
        XCTAssertEqual(controller.state?.horizontalVelocity, 0)
    }

    /// A violent flick is capped, by the same rule and to the same speed as
    /// the pet's throw.
    func test_aViolentThrowIsCapped() {
        let controller = restingToyForThrow()
        controller.grab()

        controller.release(velocity: CGPoint(x: 99_000, y: 0))

        XCTAssertEqual(controller.state?.horizontalVelocity ?? 0, MovementSolver.maxThrowSpeed, accuracy: 0.01)
    }

    /// However hard it's thrown, it has to end up back in play on screen.
    func test_aThrownToyStaysOnScreenAndSettles() {
        let controller = restingToyForThrow()
        let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
        controller.grab()
        controller.move(to: CGPoint(x: 500, y: 300))
        controller.release(velocity: CGPoint(x: 99_000, y: -2000))

        for _ in 0..<1200 {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: area)
            guard let position = controller.state?.position else { break }
            XCTAssertGreaterThanOrEqual(position.x + controller.visualBounds.minX, 0, "left the screen")
            XCTAssertLessThanOrEqual(position.x + controller.visualBounds.maxX, 1000, "left the screen")
        }

        XCTAssertEqual(controller.state?.phase, .resting, "never came to rest")
    }

    private func restingToyForThrow() -> BallController {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: CGRect(x: 0, y: 0, width: 1000, height: 600))
        return controller
    }
}

extension BallToyScaleTests {
    /// The layer takes the artwork's proportions rather than being square:
    /// the wand is 310x804, and a square box would letterbox it to a sliver.
    func test_aTallToyGetsATallLayer() {
        let wand = BallController(parent: CALayer(), toy: ToyCatalogue.wand)
        let pumpkin = BallController(parent: CALayer(), toy: ToyCatalogue.pumpkin)

        // Without artwork (no host app in tests) both fall back to the drawn
        // circle, so this only asserts what it can: the shapes differ when
        // artwork is present, and neither is ever zero-sized.
        XCTAssertGreaterThan(wand.layer.bounds.height, 0)
        XCTAssertGreaterThan(pumpkin.layer.bounds.height, 0)
        XCTAssertEqual(wand.toy, ToyCatalogue.wand)
        XCTAssertEqual(pumpkin.toy, ToyCatalogue.pumpkin)
    }
}

/// Carrying a toy above the pet's head, spinning.
final class BallToyCarryTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func toy() -> BallController {
        let controller = BallController(parent: CALayer(), toy: ToyCatalogue.wand)
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: roamableArea)
        return controller
    }

    func test_carryingPutsTheToyWhereItIsToldAndSuspendsPhysics() {
        let controller = toy()
        let overhead = CGPoint(x: 400, y: 200)

        controller.carry(to: overhead, dt: 1.0 / 60)
        for _ in 0..<120 {
            // A surface far below: gravity must not drag it down.
            controller.tick(dt: 1.0 / 60, landingY: 5000, roamableArea: roamableArea)
        }

        XCTAssertEqual(controller.state?.phase, .carried)
        XCTAssertEqual(controller.state?.position, overhead)
        XCTAssertEqual(controller.layer.position, overhead)
    }

    /// Play ending has to throw the spun toy away, not drop it where it hung.
    func test_kick_whileCarried_throwsItAway() {
        let controller = toy()
        controller.carry(to: CGPoint(x: 400, y: 200), dt: 1.0 / 60)

        controller.kick(direction: .right)

        XCTAssertEqual(controller.state?.phase, .kicked)
        XCTAssertGreaterThan(controller.state?.horizontalVelocity ?? 0, 0)
    }

    func test_carryingSpinsTheToy() {
        let controller = toy()

        controller.carry(to: CGPoint(x: 400, y: 200), dt: 0.25)
        let quarterSecond = controller.layer.affineTransform()

        XCTAssertNotEqual(quarterSecond.b, 0, "not rotating at all")
    }

    /// Frame-rate independence: the spin is an angle per second, so the same
    /// elapsed time in different-sized steps must land in the same place.
    func test_theSpinRateDoesNotDependOnFrameRate() {
        let fast = toy()
        let slow = toy()

        for _ in 0..<60 { fast.carry(to: .zero, dt: 1.0 / 60) }
        for _ in 0..<15 { slow.carry(to: .zero, dt: 1.0 / 15) }

        XCTAssertEqual(fast.layer.affineTransform().b, slow.layer.affineTransform().b, accuracy: 0.0001)
    }

    /// It must come back to physics upright -- otherwise the toy lies on its
    /// side on the floor forever after one round of play.
    func test_stopCarryingReturnsItUprightAndFalling() {
        let controller = toy()
        controller.carry(to: CGPoint(x: 400, y: 200), dt: 0.3)

        controller.stopCarrying()

        XCTAssertEqual(controller.state?.phase, .falling)
        XCTAssertEqual(controller.layer.affineTransform(), .identity, "left tilted")
    }

    /// The cursor outranks the pet: a toy being dragged must not be snatched
    /// overhead, and grabbing a spinning one straightens it.
    func test_theCursorTakesPriorityOverCarrying() {
        let controller = toy()
        controller.carry(to: CGPoint(x: 400, y: 200), dt: 0.3)

        controller.grab()
        XCTAssertEqual(controller.layer.affineTransform(), .identity, "still spinning in the hand")

        controller.carry(to: CGPoint(x: 900, y: 900), dt: 0.1)
        XCTAssertTrue(controller.isHeld, "the pet took it out of the user's hand")
    }
}

extension BallToyCarryTests {
    /// A spinning toy keeps spinning while it's in the air -- one that went
    /// rigid the moment it was thrown would look broken.
    func test_aSpinToySpinsWhileThrown() {
        let controller = toy()
        controller.grab()
        controller.move(to: CGPoint(x: 400, y: 200))
        controller.release(velocity: CGPoint(x: 500, y: -400))

        controller.tick(dt: 0.1, landingY: 5000, roamableArea: roamableArea)

        XCTAssertNotEqual(controller.layer.affineTransform().b, 0, "not spinning in flight")
    }

    /// ...and stops spinning once it lands, settling into whatever
    /// orientation that toy rests in (for the wand, on its side).
    func test_aSpinToyStopsSpinningWhenItLands() {
        let controller = toy()
        controller.grab()
        controller.move(to: CGPoint(x: 400, y: 100))
        controller.release(velocity: CGPoint(x: 300, y: 0))

        for _ in 0..<900 where controller.state?.phase != .resting {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertEqual(controller.state?.phase, .resting)
        let settled = controller.layer.affineTransform()

        // Ticking further must not move it any more -- a toy that kept
        // spinning where it lay would never look settled.
        controller.tick(dt: 0.5, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(controller.layer.affineTransform(), settled, "still turning after it landed")
    }

    /// Everything tumbles in flight, not only the toy whose whole idea is
    /// twirling. A thrown object that holds one angle the whole way across
    /// the screen reads as a picture being slid rather than a thing being
    /// thrown.
    func test_aThrownToyTumbles() {
        let controller = BallController(parent: CALayer(), toy: ToyCatalogue.pumpkin)
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: roamableArea)
        controller.grab()
        controller.release(velocity: CGPoint(x: 500, y: -400))

        controller.tick(dt: 0.1, landingY: 5000, roamableArea: roamableArea)

        XCTAssertNotEqual(controller.layer.affineTransform(), .identity)
    }

    /// And it turns the way it is going, or a toy thrown leftward rolls
    /// uphill through the air.
    func test_aThrownToyTurnsTheWayItTravels() {
        func angle(afterThrowing velocity: CGPoint) -> CGFloat {
            let controller = BallController(parent: CALayer(), toy: ToyCatalogue.pumpkin)
            controller.spawn(at: CGPoint(x: 500, y: 100))
            controller.tick(dt: 1, landingY: 500, roamableArea: roamableArea)
            controller.grab()
            controller.release(velocity: velocity)
            controller.tick(dt: 0.1, landingY: 5000, roamableArea: roamableArea)
            let t = controller.layer.affineTransform()
            return atan2(t.b, t.a)
        }

        XCTAssertGreaterThan(angle(afterThrowing: CGPoint(x: 500, y: -400)), 0)
        XCTAssertLessThan(angle(afterThrowing: CGPoint(x: -500, y: -400)), 0)
    }
}

/// A long toy comes to rest lying on its side, not standing on its end.
final class BallToyRestingOrientationTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func landed(_ toy: Toy, floor: CGFloat = 500) -> BallController {
        let controller = BallController(parent: CALayer(), toy: toy)
        controller.spawn(at: CGPoint(x: 300, y: 50))
        for _ in 0..<900 where controller.state?.phase != .resting {
            controller.tick(dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)
        }
        return controller
    }

    /// Whether the layer is turned about a quarter turn.
    private func isOnItsSide(_ controller: BallController) -> Bool {
        abs(controller.layer.affineTransform().b) > 0.9
    }

    func test_aLongToyLandsLyingDown() {
        let wand = landed(ToyCatalogue.wand)

        XCTAssertEqual(wand.state?.phase, .resting)
        XCTAssertTrue(isOnItsSide(wand), "the wand is standing on its end")
        XCTAssertGreaterThan(
            wand.visualBounds.width,
            wand.visualBounds.height,
            "its footprint must be the shape it's actually drawn in"
        )
    }

    /// Whatever orientation it rests in, it has to rest ON the floor -- the
    /// outline used for landing must match the one it ends up drawn in, or a
    /// wand hovers a stick-length above the ground or sinks into it.
    func test_aLongToyRestsExactlyOnTheFloor() {
        let floor: CGFloat = 500
        let wand = landed(ToyCatalogue.wand, floor: floor)

        XCTAssertEqual(
            (wand.state?.position.y ?? 0) + wand.visualBounds.maxY,
            floor,
            accuracy: 0.01,
            "not sitting on the floor"
        )
    }

    /// A round toy has no reason to tip over.
    func test_aRoundToyRestsUpright() {
        let pumpkin = landed(ToyCatalogue.pumpkin)

        XCTAssertFalse(isOnItsSide(pumpkin))
    }

    /// Picking it up straightens it; letting it land lies it down again.
    func test_pickingItUpStraightensItAndDroppingItLiesItDownAgain() {
        let wand = landed(ToyCatalogue.wand)
        let restingTilt = wand.layer.affineTransform()

        wand.grab()
        XCTAssertEqual(wand.layer.affineTransform(), .identity, "still tilted in the hand")

        wand.move(to: CGPoint(x: 400, y: 100))
        wand.release()
        for _ in 0..<900 where wand.state?.phase != .resting {
            wand.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertEqual(wand.layer.affineTransform(), restingTilt, "should settle the same way it did before")
    }
}

/// Bouncing a toy off whatever it just landed on.
final class BallToyBounceTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    /// Drops a toy from `height` above the surface so it arrives with real
    /// speed, as one dropped on the pet's head would.
    private func landedToy(fallingFrom height: CGFloat = 300, floor: CGFloat = 500) -> BallController {
        let controller = BallController(parent: CALayer(), toy: ToyCatalogue.pumpkin)
        controller.spawn(at: CGPoint(x: 500, y: floor - height))
        for _ in 0..<900 where controller.state?.phase != .resting {
            controller.tick(dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)
        }
        return controller
    }

    func test_bouncingSendsItBackUpAndSideways() {
        let controller = landedToy()

        controller.bounce(drift: 90)

        XCTAssertEqual(controller.state?.phase, .kicked)
        XCTAssertLessThan(controller.state?.verticalVelocity ?? 0, 0, "should be heading up")
        XCTAssertEqual(controller.state?.horizontalVelocity, 90, "should drift off the surface")
    }

    /// Proportional to the arrival, using the shared restitution -- a gentle
    /// placement and a hurled toy shouldn't bounce identically.
    func test_theBounceIsProportionalToHowHardItLanded() {
        let gentle = landedToy(fallingFrom: 40)
        let hard = landedToy(fallingFrom: 400)

        gentle.bounce(drift: 0)
        hard.bounce(drift: 0)

        XCTAssertGreaterThan(
            abs(hard.state?.verticalVelocity ?? 0),
            abs(gentle.state?.verticalVelocity ?? 0),
            "a harder landing should bounce higher"
        )
    }

    /// A toy that barely arrived has nothing left to bounce with; it stays
    /// put rather than hopping forever on ever-smaller bounces.
    func test_aToyThatBarelyLandedDoesNotBounce() {
        let controller = landedToy(fallingFrom: 1)

        controller.bounce(drift: 90)

        XCTAssertEqual(controller.state?.phase, .resting)
    }

    /// Only a toy that has actually landed -- a stray call must not relaunch
    /// one in mid-flight or snatch one out of the user's hand.
    func test_bouncingOnlyAppliesToARestingToy() {
        let controller = landedToy()
        controller.grab()

        controller.bounce(drift: 90)

        XCTAssertTrue(controller.isHeld)
    }

    /// The whole point: it ends up on the floor, not perched where it landed.
    func test_aBouncedToyMakesItsWayDownToTheFloor() {
        let floor: CGFloat = 500
        let controller = landedToy(floor: floor)
        // Landed on a "head" 200pt above the floor, then bounced off it.
        controller.spawn(at: CGPoint(x: 500, y: 100))
        for _ in 0..<900 where controller.state?.phase != .resting {
            controller.tick(dt: 1.0 / 60, landingY: 300, roamableArea: roamableArea)
        }
        controller.bounce(drift: 90)

        // From here the surface is the floor: the head has been left behind.
        for _ in 0..<1200 where controller.state?.phase != .resting {
            controller.tick(dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)
        }

        XCTAssertEqual(controller.state?.phase, .resting)
        XCTAssertEqual(
            (controller.state?.position.y ?? 0) + controller.visualBounds.maxY,
            floor,
            accuracy: 0.01,
            "never made it down to the floor"
        )
    }

    /// A toy the user throws flies as a kick and settles out of one -- which
    /// used to happen in silence, so the pet went on standing there until its
    /// own wander timer drew "go and play", up to fifteen seconds later.
    func test_tick_firesOnLanded_whenAThrownToyComesToRest() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // lands
        var settles = 0
        controller.onLanded = { _ in settles += 1 }

        controller.kick(direction: .right)
        for _ in 0..<600 where controller.state?.phase != .resting {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertEqual(controller.state?.phase, .resting)
        XCTAssertEqual(settles, 1, "coming to rest is what the pet is waiting to hear")
    }

    /// And it still says so exactly once: resting is not a repeating event.
    func test_tick_doesNotRefireOnLanded_whileTheToyStaysAtRest() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea)
        controller.kick(direction: .right)
        for _ in 0..<600 where controller.state?.phase != .resting {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        var settles = 0
        controller.onLanded = { _ in settles += 1 }
        for _ in 0..<10 {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertEqual(settles, 0)
    }

    /// The visible half of a roll: the artwork turns with the distance it
    /// covers, so it slows down and stops turning exactly as the toy does.
    func test_aRollingToyTurnsAsItTravels() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea)
        controller.kick(direction: .right)

        var sawARoll = false
        var angleWhileRolling: CGFloat = 0
        for _ in 0..<600 where controller.state?.phase != .resting {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
            if controller.state?.phase == .rolling {
                sawARoll = true
                angleWhileRolling = atan2(
                    controller.layer.affineTransform().b,
                    controller.layer.affineTransform().a
                )
            }
        }

        XCTAssertTrue(sawARoll)
        XCTAssertNotEqual(angleWhileRolling, 0, accuracy: 0.0001, "the toy slid instead of rolling")
    }
}
