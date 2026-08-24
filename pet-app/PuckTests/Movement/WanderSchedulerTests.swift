//
//  WanderSchedulerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Deterministic timer-accumulation behavior of WanderScheduler (interval/outcome
//  providers injected so the wander timer is testable).
//

import XCTest
@testable import Puck

final class WanderSchedulerTests: XCTestCase {
    /// Every other test here injects its own interval, so without this the
    /// value the app actually ships with is covered by nothing.
    func test_defaultIntervalRange_isLivelyWithoutBeingConstantMotion() {
        XCTAssertEqual(WanderScheduler.defaultIntervalRange, 8...15)
    }

    /// The provider default and the constant can drift apart, and a fixed
    /// interval makes the pet metronomic -- so pin that the shipped default
    /// both draws from the range and actually varies.
    func test_defaultInitializer_drawsVaryingIntervalsFromTheRange() {
        let range = WanderScheduler.defaultIntervalRange
        var firedAt: [TimeInterval] = []

        for _ in 0..<40 {
            let scheduler = WanderScheduler(outcomeProvider: { _ in .walkToRandomPoint })
            var elapsed: TimeInterval = 0
            while scheduler.tick(dt: 0.1) == nil {
                elapsed += 0.1
                if elapsed > range.upperBound + 1 { break }
            }
            firedAt.append(elapsed)
        }

        for interval in firedAt {
            XCTAssertGreaterThanOrEqual(interval, range.lowerBound - 0.1)
            XCTAssertLessThanOrEqual(interval, range.upperBound)
        }
        XCTAssertGreaterThan(Set(firedAt).count, 1, "a fixed interval would make the pet metronomic")
    }

    func test_tick_returnsNil_beforeIntervalElapses() {
        let scheduler = WanderScheduler(nextIntervalProvider: { _ in 10 }, outcomeProvider: { _ in .walkToRandomPoint })

        XCTAssertNil(scheduler.tick(dt: 5))
        XCTAssertNil(scheduler.tick(dt: 4.9))
    }

    func test_tick_firesOutcome_onceIntervalElapses() {
        let scheduler = WanderScheduler(nextIntervalProvider: { _ in 10 }, outcomeProvider: { _ in .climbNearestWindow })

        XCTAssertNil(scheduler.tick(dt: 9))
        XCTAssertEqual(scheduler.tick(dt: 1), .climbNearestWindow)
    }

    /// F3 ceiling-crawling (2026-07-29): a fourth Outcome case alongside walk/climb/stay.
    func test_tick_firesClimbToCeilingOutcome_onceIntervalElapses() {
        let scheduler = WanderScheduler(nextIntervalProvider: { _ in 10 }, outcomeProvider: { _ in .climbToCeiling })

        XCTAssertNil(scheduler.tick(dt: 9))
        XCTAssertEqual(scheduler.tick(dt: 1), .climbToCeiling)
    }

    /// F12 multi-toy (2026-07-30): a toy already resting on the floor only ever
    /// got played with if it happened to land while the pet was free, so
    /// anything the pet had walked away from stayed abandoned. This is the draw
    /// that goes back for it.
    func test_tick_firesPlayWithToyOutcome_onceIntervalElapses() {
        let scheduler = WanderScheduler(nextIntervalProvider: { _ in 10 }, outcomeProvider: { _ in .playWithToy })

        XCTAssertNil(scheduler.tick(dt: 9))
        XCTAssertEqual(scheduler.tick(dt: 1), .playWithToy)
    }

    /// The shipped weights, which every other test here injects around. Checked
    /// as a distribution rather than exactly: the point is that no outcome is
    /// unreachable and that playing with a toy is a minority draw, not that the
    /// numbers are precise.
    func test_weightedRandomOutcome_reachesEveryOutcome() {
        var counts: [WanderScheduler.Outcome: Int] = [:]

        for _ in 0..<4000 {
            counts[WanderScheduler.weightedRandomOutcome(), default: 0] += 1
        }

        for outcome in [
            WanderScheduler.Outcome.walkToRandomPoint, .climbNearestWindow, .climbToCeiling, .playWithToy, .stay,
        ] {
            XCTAssertGreaterThan(counts[outcome] ?? 0, 0, "\(outcome) is unreachable")
        }
        // Walking stays the most common thing the pet does.
        XCTAssertEqual(counts.max(by: { $0.value < $1.value })?.key, .walkToRandomPoint)
        XCTAssertLessThan(counts[.playWithToy] ?? 0, counts[.walkToRandomPoint] ?? 0)
    }

    func test_tick_resetsElapsedAndPicksNextInterval() {
        var intervals: [TimeInterval] = [10, 3]
        let scheduler = WanderScheduler(
            nextIntervalProvider: { _ in intervals.isEmpty ? 999 : intervals.removeFirst() },
            outcomeProvider: { _ in .stay }
        )

        XCTAssertEqual(scheduler.tick(dt: 10), .stay) // first timer (10) expires, next timer (3) is drawn
        XCTAssertNil(scheduler.tick(dt: 2))
        XCTAssertEqual(scheduler.tick(dt: 1), .stay) // second timer (3) expires
    }

    // MARK: - Pace

    /// The island is a shelf a few pets wide in the window being looked at;
    /// the desktop's eight-to-fifteen-second beat reads as a pet that has
    /// stopped working.
    func test_theIslandDrawsItsNextWanderSooner() {
        XCTAssertLessThan(
            WanderScheduler.intervalRange(for: .island).upperBound,
            WanderScheduler.intervalRange(for: .desktop).lowerBound
        )
    }

    /// Coming home in the middle of a long desktop wait, the pet would stand
    /// still on the island for the rest of it -- the first thing anybody
    /// would look at.
    func test_movingToTheIslandShortensAWaitAlreadyRunning() {
        var drawn: [WanderScheduler.Pace] = []
        let scheduler = WanderScheduler(
            nextIntervalProvider: { pace in
                drawn.append(pace)
                return pace == .desktop ? 15 : 3
            },
            outcomeProvider: { _ in .walkToRandomPoint }
        )

        // 8 seconds into a 15-second desktop wait, the pet goes home.
        for _ in 0..<8 { XCTAssertNil(scheduler.tick(dt: 1)) }
        scheduler.pace = .island

        // The wait is now the island's longest, not the desktop's: it fires
        // within seven seconds rather than at fifteen.
        var fired: WanderScheduler.Outcome?
        for _ in 0..<7 { fired = scheduler.tick(dt: 1) ?? fired }
        XCTAssertEqual(fired, .walkToRandomPoint)
        XCTAssertEqual(drawn.last, .island, "and the next wait is drawn for where it now is")
    }

    /// Nothing on the island can be climbed and no toy lies on it, so those
    /// draws would fall through to a walk anyway. Standing still is drawn on
    /// its own terms, and one wander in six spent still is a lot on a shelf.
    func test_theIslandStandsStillLessOften() {
        let draws = (0..<2000).map { _ in WanderScheduler.weightedRandomOutcome(pace: .island) }
        let stays = draws.filter { $0 == .stay }.count

        XCTAssertTrue(draws.allSatisfy { $0 == .walkToRandomPoint || $0 == .stay })
        XCTAssertLessThan(stays, draws.count / 8)
    }
}
