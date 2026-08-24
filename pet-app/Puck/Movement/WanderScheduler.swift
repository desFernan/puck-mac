//
//  WanderScheduler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Idle's 8-30s random wander timer, weighted next-action selection.
//

import Foundation

/// The wander timer owned by IdleState. Accumulates dt; once the timer
/// expires, draws and returns the next Outcome, then draws its own next
/// interval. Randomness is injectable so tests can verify it deterministically.
final class WanderScheduler {
    enum Outcome: Hashable {
        /// Move to a random point (Walk)
        case walkToRandomPoint
        /// Move to and climb the nearest window (Climb)
        case climbNearestWindow
        /// Climb straight up to the ceiling and crawl there (F3 ceiling-crawling, 2026-07-29)
        case climbToCeiling
        /// Go and play with a toy that is lying about (F12 multi-toy, 2026-07-30).
        /// Without this draw, play could only ever start at the moment a toy
        /// LANDED -- so a toy the pet had already kicked away and walked off
        /// from was abandoned for good, and with several toys out that was the
        /// normal case rather than an edge one.
        case playWithToy
        /// Stay idle this round
        case stay
    }

    /// How long Idle waits before drawing its next Outcome.
    ///
    /// 02_pet-app.md F3 specified `8...30`, and both ends of that were wrong
    /// in practice, in opposite directions:
    ///
    /// - 30s at the top read as broken rather than calm. Measured, the pet
    ///   walked a few seconds and then froze for over 20, which looks like its
    ///   motion is stuttering to a halt.
    /// - A flat 5s (tried next) overcorrected: sampling the frame loop showed
    ///   the pet in motion on essentially every frame of every window, and one
    ///   `.climbToCeiling` draw chains ~12s of climb plus ceiling plus fall on
    ///   top of that, so it effectively never rested.
    ///
    /// 8...15 keeps it visibly alive without it being in constant motion. It
    /// stays a *range* because a fixed interval makes the pet metronomic --
    /// the one thing a wander timer exists to avoid.
    ///
    /// Note this is the wait between *draws*, not between moves: 15% of draws
    /// come back `.stay`, so some observed rests span two intervals.
    static let defaultIntervalRange: ClosedRange<TimeInterval> = 8...15

    /// Where the pet is, which is also how busy it should look.
    enum Pace: Hashable {
        /// The whole desktop. There is a lot of it, the pet is off to one
        /// side of whatever the user is doing, and constant motion in the
        /// corner of the eye is the thing this timer exists to avoid.
        case desktop
        /// The island. A shelf a few pets wide, in the window being looked
        /// at -- and a pet that stands still on it for fifteen seconds reads
        /// as one that has stopped working. Short trips, taken often.
        case island
    }

    /// The island's range. Not simply "smaller numbers": a wander is one to
    /// three legs with pauses, so the draw interval is the gap *between*
    /// wanders, and 3-7 there puts the pet in motion for about half the time
    /// rather than a tenth of it.
    static let islandIntervalRange: ClosedRange<TimeInterval> = 3...7

    static func intervalRange(for pace: Pace) -> ClosedRange<TimeInterval> {
        switch pace {
        case .desktop: return defaultIntervalRange
        case .island: return islandIntervalRange
        }
    }

    /// Changed when the pet moves in or out of its tank.
    ///
    /// Shortens a wait already running rather than only the next one: coming
    /// home in the middle of a fifteen-second desktop interval, the pet stood
    /// on the island doing nothing for the rest of it, which is the first
    /// thing anybody would look at.
    var pace: Pace = .desktop {
        didSet {
            guard pace != oldValue else { return }
            nextFireInterval = min(nextFireInterval, Self.intervalRange(for: pace).upperBound)
        }
    }

    private var elapsed: TimeInterval = 0
    private var nextFireInterval: TimeInterval
    private let nextIntervalProvider: (Pace) -> TimeInterval
    private let outcomeProvider: (Pace) -> Outcome

    init(
        nextIntervalProvider: @escaping (Pace) -> TimeInterval = {
            .random(in: WanderScheduler.intervalRange(for: $0))
        },
        outcomeProvider: @escaping (Pace) -> Outcome = WanderScheduler.weightedRandomOutcome(pace:)
    ) {
        self.nextIntervalProvider = nextIntervalProvider
        self.outcomeProvider = outcomeProvider
        self.nextFireInterval = nextIntervalProvider(.desktop)
    }

    /// Accumulates dt. Once elapsed time passes the timer, returns an Outcome
    /// and resets the timer + draws the next interval.
    @discardableResult
    func tick(dt: TimeInterval) -> Outcome? {
        elapsed += dt
        guard elapsed >= nextFireInterval else { return nil }
        elapsed = 0
        nextFireInterval = nextIntervalProvider(pace)
        return outcomeProvider(pace)
    }

    /// Default weights: 35% random move, 25% climb nearest window, 15% climb
    /// to the ceiling, 10% play with a toy, 15% stay.
    ///
    /// The toy draw was taken out of walking's share rather than out of the
    /// climbs: walking is the filler behaviour, and it is also what the pet
    /// falls back to when the draw can't be honoured (no toy is out, nothing
    /// to climb), so borrowing from it doesn't change how often the pet ends
    /// up walking as much as the numbers suggest.
    static func weightedRandomOutcome(pace: Pace = .desktop) -> Outcome {
        // Nothing on the island can be climbed and no toy is lying on it, so
        // those three draws would all fall through to a walk anyway -- but
        // `.stay` is drawn on its own terms, and one in six wanders spent
        // standing still is a lot on a shelf. Half as often there.
        guard pace == .desktop else {
            return Double.random(in: 0..<1) < 0.92 ? .walkToRandomPoint : .stay
        }
        switch Double.random(in: 0..<1) {
        case ..<0.35: return .walkToRandomPoint
        case ..<0.60: return .climbNearestWindow
        case ..<0.75: return .climbToCeiling
        case ..<0.85: return .playWithToy
        default: return .stay
        }
    }
}
