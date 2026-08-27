//
//  RoamPointTests.swift
//  Puck
//
//  Where a wander goes. Drawn as a distance from where the pet already is,
//  because a uniform draw over the whole width made nearly every wander a
//  full crossing -- the same trip, over and over (2026-08-22).
//

import XCTest
import CoreGraphics
@testable import Puck

final class RoamPointTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private var limits: ClosedRange<CGFloat> {
        let margin = area.width * AppDelegate.roamEdgeMargin
        return (area.minX + margin)...(area.maxX - margin)
    }

    func test_targetsStayInsideTheEdgeMargin() {
        for start in stride(from: CGFloat(0), through: 1000, by: 50) {
            for _ in 0..<50 {
                let point = AppDelegate.randomRoamPoint(in: area, from: start)
                XCTAssertTrue(limits.contains(point.x), "\(point.x) from \(start)")
                XCTAssertEqual(point.y, area.maxY, "wander targets are on the floor")
            }
        }
    }

    /// The point of the change: most draws are near, some are far. A uniform
    /// draw would put about half of them past a third of the screen.
    func test_mostWandersAreShortHops() {
        let start: CGFloat = 500
        let distances = (0..<400).map { _ in abs(AppDelegate.randomRoamPoint(in: area, from: start).x - start) }
        let short = distances.filter { $0 <= area.width * 0.3 }.count

        XCTAssertGreaterThan(short, 240, "at least ~60% short, by the 75/25 split")
        XCTAssertTrue(distances.contains { $0 > area.width * 0.3 }, "but not always short")
    }

    func test_thePetGoesBothWays() {
        let start: CGFloat = 500
        let points = (0..<200).map { _ in AppDelegate.randomRoamPoint(in: area, from: start).x }

        XCTAssertTrue(points.contains { $0 < start })
        XCTAssertTrue(points.contains { $0 > start })
    }

    /// A pet already pressed against the margin still gets somewhere to go --
    /// the draw is reflected back inwards rather than clamped onto the edge.
    func test_fromTheEdge_itMovesInwards() {
        let atEdge = limits.lowerBound
        let points = (0..<100).map { _ in AppDelegate.randomRoamPoint(in: area, from: atEdge).x }

        XCTAssertTrue(points.allSatisfy { $0 >= limits.lowerBound })
        XCTAssertTrue(points.contains { $0 > atEdge + 20 }, "it does not just sit on the margin")
    }

    func test_aZeroWidthAreaDoesNotCrash() {
        XCTAssertEqual(AppDelegate.randomRoamPoint(in: .zero, from: 0), .zero)
    }

    // MARK: - Legs (2026-08-22)

    /// One trip and a long sit was the shape that read as monotonous, so a
    /// wander is walked in legs with a beat between them.
    func test_wanderLegs_areMostlyOneSometimesMore() {
        let draws = (0..<600).map { _ in WanderRun.drawLegs() }

        XCTAssertTrue(draws.allSatisfy { (1...3).contains($0) })
        XCTAssertGreaterThan(draws.filter { $0 == 1 }.count, 250, "most wanders stay one leg")
        XCTAssertGreaterThan(draws.filter { $0 > 1 }.count, 100, "but a good share meander")
    }

    /// Long enough to look like the pet stopped to consider something, short
    /// enough that the legs still read as one wander rather than two.
    func test_legPause_isABeatNotARest() {
        let pauses = (0..<100).map { _ in WanderRun.drawPause() }

        XCTAssertTrue(pauses.allSatisfy { $0 >= 0.4 && $0 <= 1.4 })
        XCTAssertGreaterThan(Set(pauses.map { Int($0 * 10) }).count, 3, "not a fixed beat")
    }

    // MARK: - Wandering at home (2026-08-22)

    /// The window list is the desktop's, not the tank's: a pet at home that
    /// drew "climb the nearest window" would walk at a window outside its own
    /// glass, and there is no ceiling in a 90pt strip.
    func test_atHome_climbingOutcomesBecomeAWalk() {
        XCTAssertEqual(AppDelegate.wanderOutcome(.climbNearestWindow, atHome: true), .walkToRandomPoint)
        XCTAssertEqual(AppDelegate.wanderOutcome(.climbToCeiling, atHome: true), .walkToRandomPoint)
    }

    func test_atHome_everythingElseIsUnchanged() {
        XCTAssertEqual(AppDelegate.wanderOutcome(.walkToRandomPoint, atHome: true), .walkToRandomPoint)
        XCTAssertEqual(AppDelegate.wanderOutcome(.playWithToy, atHome: true), .playWithToy)
        XCTAssertEqual(AppDelegate.wanderOutcome(.stay, atHome: true), .stay)
    }

    func test_onTheDesktop_nothingIsFilteredAtAll() {
        XCTAssertEqual(AppDelegate.wanderOutcome(.climbNearestWindow, atHome: false), .climbNearestWindow)
        XCTAssertEqual(AppDelegate.wanderOutcome(.climbToCeiling, atHome: false), .climbToCeiling)
    }

    // MARK: - Reduce Motion

    /// A wander is the one movement in the app nobody asked for: it starts on
    /// a timer, next to whatever the person is actually reading. With the
    /// system setting on, the draw comes out as "stay" wherever the pet is
    /// and whatever it rolled.
    func test_reduceMotion_turnsEveryWanderIntoStayingPut() {
        for outcome in [
            WanderScheduler.Outcome.walkToRandomPoint,
            .climbNearestWindow,
            .climbToCeiling,
            .playWithToy,
            .stay,
        ] {
            XCTAssertEqual(AppDelegate.wanderOutcome(outcome, atHome: false, reduceMotion: true), .stay)
            XCTAssertEqual(AppDelegate.wanderOutcome(outcome, atHome: true, reduceMotion: true), .stay)
        }
    }

    /// And off, nothing changes -- the setting is the only thing that decides
    /// this, so a pet that stopped wandering for anybody else would be a bug
    /// with no way to tell it from the feature.
    func test_withoutReduceMotion_theDrawIsUntouched() {
        XCTAssertEqual(AppDelegate.wanderOutcome(.climbToCeiling, atHome: false, reduceMotion: false), .climbToCeiling)
        XCTAssertEqual(AppDelegate.wanderOutcome(.walkToRandomPoint, atHome: false, reduceMotion: false), .walkToRandomPoint)
    }

    /// The island is small enough that one leg of it is barely a step, so a
    /// wander there is made of more of them, with less standing about between.
    func test_aWanderOnTheIslandHasMoreLegsAndShorterPauses() {
        let home = (0..<600).map { _ in WanderRun.drawLegs(atHome: true) }
        let desktop = (0..<600).map { _ in WanderRun.drawLegs(atHome: false) }

        XCTAssertTrue(home.allSatisfy { (2...4).contains($0) })
        XCTAssertGreaterThan(
            home.reduce(0, +) / home.count,
            desktop.reduce(0, +) / desktop.count
        )
        XCTAssertTrue((0..<100).allSatisfy { _ in WanderRun.drawPause(atHome: true) <= 0.7 })
    }
}
