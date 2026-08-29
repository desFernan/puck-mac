//
//  BouncePresetTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Pure math for the 2026-07-29 2D switch's procedural squash-and-stretch
//  "bounce" motion (F2) -- no rendering, no timers, just
//  elapsed-time-in, transform-out.
//

import XCTest
@testable import Puck

final class BouncePresetTests: XCTestCase {
    // MARK: - preset(for:) mapping

    func test_preset_mapsIdleWalkLand() {
        XCTAssertEqual(BouncePreset.preset(for: "idle"), .idle)
        XCTAssertEqual(BouncePreset.preset(for: "walk"), .walk)
        XCTAssertEqual(BouncePreset.preset(for: "land"), .land)
    }

    func test_preset_mapsPointAndReactClickToPop() {
        XCTAssertEqual(BouncePreset.preset(for: "point"), .pop)
        XCTAssertEqual(BouncePreset.preset(for: "react_click"), .pop)
    }

    func test_preset_mapsKickToKick() {
        XCTAssertEqual(BouncePreset.preset(for: "kick"), .kick)
    }

    func test_preset_mapsPetToWiggle() {
        XCTAssertEqual(BouncePreset.preset(for: "pet"), .wiggle)
    }

    func test_preset_mapsUnhandledClipsToNone() {
        for clip in ["fall", "type", "listen", "react_drag", "not_a_real_clip"] {
            XCTAssertEqual(BouncePreset.preset(for: clip), .none, "expected .none for \(clip)")
        }
    }

    // MARK: - intensity 0 / .none -> always identity

    func test_transform_zeroIntensity_isAlwaysIdentity() {
        for preset: BouncePreset in [.idle, .walk, .land, .pop, .kick, .wiggle] {
            let transform = preset.transform(elapsed: 1.0, intensity: 0)
            XCTAssertEqual(transform, .identity, "expected identity for \(preset) at intensity 0")
        }
    }

    func test_transform_noneCase_isAlwaysIdentityRegardlessOfIntensity() {
        XCTAssertEqual(BouncePreset.none.transform(elapsed: 0.5, intensity: 1.0), .identity)
    }

    // MARK: - idle: slow bob

    func test_idle_atZeroElapsed_isIdentity() {
        let transform = BouncePreset.idle.transform(elapsed: 0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.0001)
    }

    func test_idle_atQuarterPeriod_peaksScaleYAboveOne() {
        let period = 2.5
        let transform = BouncePreset.idle.transform(elapsed: period / 4, intensity: 1.0)
        XCTAssertGreaterThan(transform.scaleY, 1.0)
    }

    // MARK: - walk: faster bounce

    func test_walk_atZeroElapsed_isIdentity() {
        let transform = BouncePreset.walk.transform(elapsed: 0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.0001)
    }

    /// The horizontal squeeze used to fold on abs(sin), which has a
    /// derivative kink at every zero-crossing (footfall) -- the motion
    /// visibly "caught" there. sin^2 keeps the same range (0 at rest, full
    /// squeeze at the peak) but eases through zero instead of folding.
    func test_walk_squeezeUsesASmoothQuadraticFalloff_notALinearFold() {
        let period = 0.35
        let elapsed = period / 12 // sin(2*pi*elapsed/period) == sin(pi/6) == 0.5
        let transform = BouncePreset.walk.transform(elapsed: elapsed, intensity: 1.0)

        XCTAssertEqual(transform.scaleX, 1 - 0.08 * 0.3 * 0.25, accuracy: 0.0005)
    }

    // MARK: - land: squash on impact, springs back

    func test_land_atZeroElapsed_squashesAtFullIntensity() {
        let transform = BouncePreset.land.transform(elapsed: 0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.3, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 0.7, accuracy: 0.0001)
    }

    func test_land_decaysToIdentity_wellAfterItsDuration() {
        let transform = BouncePreset.land.transform(elapsed: 5.0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.01)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.01)
    }

    // MARK: - pop: point/react_click pulse

    func test_pop_atZeroElapsed_isIdentity() {
        let transform = BouncePreset.pop.transform(elapsed: 0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.0001)
    }

    func test_pop_atHalfDuration_peaksAboveOne() {
        let transform = BouncePreset.pop.transform(elapsed: 0.125, intensity: 1.0) // duration 0.25
        XCTAssertEqual(transform.scaleX, 1.15, accuracy: 0.001)
        XCTAssertEqual(transform.scaleY, 1.15, accuracy: 0.001)
    }

    func test_pop_afterDuration_staysAtRest() {
        // t is clamped past 1.0, so sin(pi) == 0 -- not decaying further, just resting.
        let transform = BouncePreset.pop.transform(elapsed: 10, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.0001)
    }

    // MARK: - kick: anticipation squash, then impact stretch

    func test_kick_earlyElapsed_squashesInAnticipation() {
        let transform = BouncePreset.kick.transform(elapsed: 0.1, intensity: 1.0) // < 0.4 * 0.4 = 0.16 threshold
        XCTAssertGreaterThan(transform.scaleX, 1.0)
        XCTAssertLessThan(transform.scaleY, 1.0)
    }

    func test_kick_lateElapsed_stretchesOnImpact() {
        let transform = BouncePreset.kick.transform(elapsed: 0.3, intensity: 1.0) // past the 0.16s anticipation threshold
        XCTAssertLessThan(transform.scaleX, 1.0)
        XCTAssertGreaterThan(transform.scaleY, 1.0)
    }

    // MARK: - wiggle: petting reaction (2026-07-29)

    func test_wiggle_atZeroElapsed_isIdentity() {
        let transform = BouncePreset.wiggle.transform(elapsed: 0, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.0001)
    }

    func test_wiggle_oscillatesSideToSide() {
        // Near an odd multiple of the wiggle's quarter-period, scaleX should
        // be visibly off from identity in one direction or the other.
        let transform = BouncePreset.wiggle.transform(elapsed: 0.0375, intensity: 1.0) // 0.15s period / 4
        XCTAssertNotEqual(transform.scaleX, 1.0, accuracy: 0.001)
    }

    func test_wiggle_decaysToIdentity_byTheEndOfItsDuration() {
        let transform = BouncePreset.wiggle.transform(elapsed: 0.8, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.01)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.01)
    }

    /// The old two-phase linear ramp jumped from its anticipation peak
    /// straight to its impact peak at the phase boundary instead of passing
    /// through identity -- a visible "snap" mid-kick. Both phases must meet
    /// at identity so the curve reads as one continuous motion.
    func test_kick_isContinuousAcrossThePhaseBoundary() {
        let boundary = 0.4 * 0.4 // anticipation window (duration * its fraction)
        let justBefore = BouncePreset.kick.transform(elapsed: boundary - 0.001, intensity: 1.0)
        let justAfter = BouncePreset.kick.transform(elapsed: boundary + 0.001, intensity: 1.0)

        XCTAssertEqual(justBefore.scaleX, justAfter.scaleX, accuracy: 0.01)
        XCTAssertEqual(justBefore.scaleY, justAfter.scaleY, accuracy: 0.01)
    }

    func test_kick_atPhaseBoundary_passesThroughIdentity() {
        let boundary = 0.4 * 0.4
        let transform = BouncePreset.kick.transform(elapsed: boundary, intensity: 1.0)
        XCTAssertEqual(transform.scaleX, 1.0, accuracy: 0.001)
        XCTAssertEqual(transform.scaleY, 1.0, accuracy: 0.001)
    }
}

/// The climb waddle.
final class ClimbBouncePresetTests: XCTestCase {
    private let preset = BouncePreset.climb

    func test_climbClipUsesTheWaddle() {
        XCTAssertEqual(BouncePreset.preset(for: "climb"), .climb)
    }

    /// Rotation is the whole effect — a scale-only waddle reads as the sprite
    /// being squeezed rather than the pet leaning.
    func test_rocksBothWaysOverOneCycle() {
        let quarter = preset.transform(elapsed: 0.125, intensity: 1) // sin peak
        let threeQuarter = preset.transform(elapsed: 0.375, intensity: 1) // sin trough

        XCTAssertGreaterThan(quarter.rotation, 0, "leaning one way")
        XCTAssertLessThan(threeQuarter.rotation, 0, "and the other")
        XCTAssertEqual(quarter.rotation, -threeQuarter.rotation, accuracy: 0.0001, "symmetrically")
    }

    func test_leanStaysGentle() {
        for step in 0...40 {
            let rotation = preset.transform(elapsed: Double(step) * 0.02, intensity: 1).rotation

            XCTAssertLessThanOrEqual(abs(rotation), 8 * .pi / 180 + 0.0001, "never leans more than 8 degrees")
        }
    }

    func test_intensityScalesTheLean() {
        let full = preset.transform(elapsed: 0.125, intensity: 1).rotation
        let half = preset.transform(elapsed: 0.125, intensity: 0.5).rotation

        XCTAssertEqual(half, full / 2, accuracy: 0.0001)
    }

    func test_zeroIntensityIsCompletelyStill() {
        XCTAssertEqual(preset.transform(elapsed: 0.125, intensity: 0), .identity)
    }

    /// The squash runs at twice the rocking rate: shortest at both extremes
    /// of the lean, tallest passing through upright. Matched frequencies
    /// would make one side droop instead.
    ///
    /// Measured as a magnitude, because the sign carries something else: the
    /// climb's scaleY is negative, which is half of turning the pet over to
    /// face the wall -- see the preset. The squash is how far from 1 it is.
    func test_squashPeaksAtBothExtremesOfTheLean() {
        let upright = abs(preset.transform(elapsed: 0, intensity: 1).scaleY)
        let leaningRight = abs(preset.transform(elapsed: 0.125, intensity: 1).scaleY)
        let leaningLeft = abs(preset.transform(elapsed: 0.375, intensity: 1).scaleY)

        XCTAssertEqual(upright, 1, accuracy: 0.0001, "tallest passing through upright")
        XCTAssertLessThan(leaningRight, upright)
        XCTAssertEqual(leaningLeft, leaningRight, accuracy: 0.0001, "equally short both ways")
    }

    /// The climb is the one preset that turns the pet over rather than only
    /// squashing it: a quarter turn onto the wall, and a mirror on each axis
    /// so it climbs feet-first instead of head-first.
    func test_theClimbTurnsThePetOntoTheWall() {
        let transform = preset.transform(elapsed: 0, intensity: 1)

        XCTAssertTrue(transform.rotatesQuarterTurn)
        XCTAssertLessThan(transform.scaleX, 0, "mirrored across")
        XCTAssertLessThan(transform.scaleY, 0, "and over")
    }

    /// Every other preset must stay purely a scale transform.
    func test_otherPresetsDoNotRotate() {
        for other in [BouncePreset.none, .idle, .walk, .land, .pop, .kick, .wiggle] {
            for step in 0...20 {
                let rotation = other.transform(elapsed: Double(step) * 0.05, intensity: 1).rotation
                XCTAssertEqual(rotation, 0, "\(other) must not rotate")
            }
        }
    }
}
