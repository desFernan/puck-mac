//
//  AgentScheduleTests.swift
//  PuckTests
//
//  When a scheduled run comes round.
//
//  Against a fixed clock, because every case worth testing is one: a daily
//  time that has already gone today, a weekly one on the day itself, and a
//  schedule made moments ago.
//

import XCTest
@testable import Puck

final class AgentScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // Fixed, so the suite does not pass in Seoul and fail in a CI runner
        // set to UTC.
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func schedule(_ cadence: AgentSchedule.Cadence, created: String, lastFired: String? = nil) -> AgentSchedule {
        AgentSchedule(
            prompt: "CI 확인해줘",
            workspaceId: "w1",
            cadence: cadence,
            lastFiredAt: lastFired.map(date),
            createdAt: date(created)
        )
    }

    // MARK: - Every so many minutes

    /// Counted from when it was made, so one created at 3pm and set to run
    /// hourly first runs at 4 rather than immediately.
    func test_anIntervalCountsFromWhenItWasMade() {
        let every = schedule(.everyMinutes(60), created: "2026-09-05 15:00")

        XCTAssertEqual(every.nextFire(calendar: calendar), date("2026-09-05 16:00"))
        XCTAssertFalse(every.isDue(at: date("2026-09-05 15:30"), calendar: calendar))
        XCTAssertTrue(every.isDue(at: date("2026-09-05 16:00"), calendar: calendar))
    }

    /// And from the last run once there has been one.
    func test_anIntervalCountsFromTheLastRun() {
        let every = schedule(.everyMinutes(30), created: "2026-09-05 09:00", lastFired: "2026-09-05 15:00")

        XCTAssertEqual(every.nextFire(calendar: calendar), date("2026-09-05 15:30"))
    }

    // MARK: - Daily

    /// Later today when the time is still to come.
    func test_aDailyTimeStillToComeIsToday() {
        let daily = schedule(.daily(hour: 9, minute: 30), created: "2026-09-05 08:00")

        XCTAssertEqual(daily.nextFire(calendar: calendar), date("2026-09-05 09:30"))
    }

    /// And tomorrow when it has gone -- the case a naive "set the hour on
    /// today's date" gets wrong, firing immediately and then every tick.
    func test_aDailyTimeThatHasGoneIsTomorrow() {
        let daily = schedule(.daily(hour: 9, minute: 30), created: "2026-09-05 08:00", lastFired: "2026-09-05 09:30")

        XCTAssertEqual(daily.nextFire(calendar: calendar), date("2026-09-06 09:30"))
        XCTAssertFalse(daily.isDue(at: date("2026-09-05 23:59"), calendar: calendar))
        XCTAssertTrue(daily.isDue(at: date("2026-09-06 09:30"), calendar: calendar))
    }

    // MARK: - Weekly

    /// 2026-09-07 is a Monday; `Calendar` numbers Monday 2.
    func test_aWeeklyScheduleWaitsForOneOfItsDays() {
        let weekly = schedule(.weekly(days: [2], hour: 9, minute: 0), created: "2026-09-05 08:00")

        XCTAssertEqual(
            weekly.nextFire(calendar: calendar),
            date("2026-09-07 09:00")
        )
    }

    /// On the day itself, before the time: today.
    func test_aWeeklyScheduleOnItsOwnDayIsToday() {
        // 2026-09-05 is a Saturday, which Calendar numbers 7.
        let weekly = schedule(.weekly(days: [7], hour: 18, minute: 0), created: "2026-09-05 08:00")

        XCTAssertEqual(
            weekly.nextFire(calendar: calendar),
            date("2026-09-05 18:00")
        )
    }

    /// No days is a schedule that never comes round, not one that runs
    /// constantly -- which is what an empty set would mean to a check that
    /// asked "is today in the list" the other way about.
    func test_aWeeklyScheduleWithNoDaysNeverFires() {
        let weekly = schedule(.weekly(days: [], hour: 9, minute: 0), created: "2026-09-05 08:00")

        XCTAssertNil(weekly.nextFire(calendar: calendar))
        XCTAssertFalse(weekly.isDue(at: date("2026-09-30 08:00"), calendar: calendar))
    }

    // MARK: - Off, and missed

    func test_aSwitchedOffScheduleNeverFires() {
        var daily = schedule(.daily(hour: 9, minute: 0), created: "2026-09-05 08:00")
        daily.isEnabled = false

        XCTAssertNil(daily.nextFire(calendar: calendar))
        XCTAssertFalse(daily.isDue(at: date("2026-09-06 12:00"), calendar: calendar))
    }

    /// One whose time passed while the app was shut is due the moment it
    /// comes back -- once, not once per missed occurrence. Nobody wants
    /// yesterday's seven hourly checks all at once.
    func test_aScheduleMissedWhileTheAppWasShutIsDueOnce() {
        let every = schedule(.everyMinutes(60), created: "2026-09-01 09:00")

        XCTAssertTrue(every.isDue(at: date("2026-09-05 09:00"), calendar: calendar))
    }

    /// Nonsense is refused rather than turned into a tight loop.
    func test_anIntervalOfZeroNeverFires() {
        XCTAssertNil(schedule(.everyMinutes(0), created: "2026-09-05 09:00")
            .nextFire(calendar: calendar))
    }

    /// It has to survive a restart, which is the whole of what a schedule is
    /// for.
    func test_aScheduleSurvivesBeingWrittenDown() throws {
        let original = schedule(.weekly(days: [2, 4], hour: 9, minute: 30), created: "2026-09-05 08:00")

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(AgentSchedule.self, from: data)

        XCTAssertEqual(restored, original)
    }
}

@MainActor
final class AgentScheduleStoreTests: XCTestCase {
    private var storageURL: URL!

    override func setUpWithError() throws {
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("schedules.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
    }

    func test_schedulesSurviveARestart() {
        let first = AgentScheduleStore(storageURL: storageURL)
        first.add(AgentSchedule(prompt: "확인", workspaceId: "w1", cadence: .everyMinutes(30)))

        let second = AgentScheduleStore(storageURL: storageURL)

        XCTAssertEqual(second.schedules.count, 1)
        XCTAssertEqual(second.schedules.first?.prompt, "확인")
    }

    /// Marked as fired *before* the callback: `onDue` starts an agent turn,
    /// and a turn that throws -- or an app that quits during one -- must not
    /// leave the schedule looking due forever and firing on every tick.
    func test_oneThatFiredIsNotDueAgainOnTheNextTick() {
        let store = AgentScheduleStore(storageURL: storageURL)
        store.add(AgentSchedule(
            prompt: "확인",
            workspaceId: "w1",
            cadence: .everyMinutes(60),
            createdAt: Date(timeIntervalSince1970: 0)
        ))
        var fired = 0
        store.onDue = { _ in fired += 1 }

        let now = Date(timeIntervalSince1970: 10_000)
        store.tick(now: now)
        store.tick(now: now)

        XCTAssertEqual(fired, 1)
    }

    /// A workspace that has gone takes its schedules with it: they name a
    /// project that no longer exists, so they can never run again.
    func test_deletingAWorkspaceTakesItsSchedules() {
        let store = AgentScheduleStore(storageURL: storageURL)
        store.add(AgentSchedule(prompt: "a", workspaceId: "w1", cadence: .everyMinutes(30)))
        store.add(AgentSchedule(prompt: "b", workspaceId: "w2", cadence: .everyMinutes(30)))

        store.removeAll(inWorkspace: "w1")

        XCTAssertEqual(store.schedules.map(\.workspaceId), ["w2"])
    }

    func test_switchingOneOffStopsItFiring() {
        let store = AgentScheduleStore(storageURL: storageURL)
        store.add(AgentSchedule(
            prompt: "확인",
            workspaceId: "w1",
            cadence: .everyMinutes(1),
            createdAt: Date(timeIntervalSince1970: 0)
        ))
        var fired = 0
        store.onDue = { _ in fired += 1 }

        store.setEnabled(false, id: store.schedules[0].id)
        store.tick(now: Date(timeIntervalSince1970: 10_000))

        XCTAssertEqual(fired, 0)
    }
}
