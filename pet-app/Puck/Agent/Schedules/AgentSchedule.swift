//
//  AgentSchedule.swift
//  Puck
//
//  Something to do, later, on a repeat.
//
//  "매일 아침 CI 확인해서 깨졌으면 알려줘" is the request a pet living on your
//  desktop is most obviously for, and there was no way to say it. Orca has
//  cron automations for the same reason.
//
//  Deliberately not cron. A cron expression is a small language that people
//  get wrong -- and every schedule anyone actually wants here is one of three
//  shapes: every so many minutes, once a day at a time, or on the days of the
//  week you pick. Those are what this offers, and each of them can be said in
//  a sentence in the UI.
//
//  Only while Puck is running, and that is not a limitation to work around: a
//  scheduled run drives the pet and the chat window, and a launchd job that
//  fires with the app closed has nothing to drive. A schedule whose time
//  passed while the app was shut runs when it comes back, once -- see
//  `nextFire`.
//
//  Pure, and separate from the timer, because every case worth testing is a
//  clock: a daily time that has already passed today, a weekly one on the day
//  itself, and the moment a schedule is created.
//

import Foundation

struct AgentSchedule: Codable, Equatable, Identifiable {
    /// How often it comes round.
    enum Cadence: Codable, Equatable {
        /// Every `minutes`, from when it was created.
        case everyMinutes(Int)
        /// Once a day, at `hour`:`minute` local time.
        case daily(hour: Int, minute: Int)
        /// On the given weekdays, at `hour`:`minute`. Weekdays are
        /// `Calendar`'s own numbering, 1 = Sunday.
        case weekly(days: Set<Int>, hour: Int, minute: Int)
    }

    let id: String
    /// What to send, exactly as though it had been typed into the chat.
    var prompt: String
    /// Which workspace it runs in. A schedule belongs to a project the same
    /// way a conversation does -- "check CI" means nothing without one.
    var workspaceId: String
    var cadence: Cadence
    var isEnabled: Bool
    /// When it last ran, so a missed one can be told from a fresh one.
    var lastFiredAt: Date?
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        prompt: String,
        workspaceId: String,
        cadence: Cadence,
        isEnabled: Bool = true,
        lastFiredAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.workspaceId = workspaceId
        self.cadence = cadence
        self.isEnabled = isEnabled
        self.lastFiredAt = lastFiredAt
        self.createdAt = createdAt
    }

    /// When this should next run.
    ///
    /// A function of when it last ran and nothing else -- not of what time it
    /// is now. That distinction is the whole of `isDue` being right: asking
    /// for the next occurrence *after now* means a schedule is never due at
    /// the moment it comes round, only after it, so the answer at exactly
    /// 09:30 for a 09:30 daily was tomorrow.
    ///
    /// From `lastFiredAt` when there is one and from `createdAt` when there
    /// is not, so a schedule made at 3pm and set to run every hour first runs
    /// at 4pm rather than immediately.
    ///
    /// - Returns: nil when it is switched off, or when a weekly schedule
    ///   names no days -- which is a schedule that never comes round rather
    ///   than one that runs constantly.
    func nextFire(calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        let since = lastFiredAt ?? createdAt
        switch cadence {
        case .everyMinutes(let minutes):
            guard minutes > 0 else { return nil }
            return since.addingTimeInterval(TimeInterval(minutes) * 60)
        case .daily(let hour, let minute):
            return Self.nextTime(hour: hour, minute: minute, after: since, on: nil, calendar: calendar)
        case .weekly(let days, let hour, let minute):
            guard !days.isEmpty else { return nil }
            return Self.nextTime(hour: hour, minute: minute, after: since, on: days, calendar: calendar)
        }
    }

    /// Whether it is due at `now`.
    ///
    /// A schedule whose time passed while the app was shut is due the moment
    /// it comes back. Once, not once per missed occurrence: nobody wants
    /// yesterday's seven hourly checks all at once, and the answer to "what
    /// is the state of things" is the same whether it is asked once or seven
    /// times.
    func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let next = nextFire(calendar: calendar) else { return false }
        return next <= now
    }

    /// The next `hour`:`minute` strictly after `reference`, optionally
    /// restricted to certain weekdays.
    private static func nextTime(
        hour: Int,
        minute: Int,
        after reference: Date,
        on days: Set<Int>?,
        calendar: Calendar
    ) -> Date? {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        // Fourteen days is two full weeks, which is more than enough to find
        // the next occurrence of any weekday -- and a bound, so a set of days
        // that somehow matches nothing cannot loop forever.
        var candidate = calendar.startOfDay(for: reference)
        for _ in 0...14 {
            if let time = calendar.date(
                bySettingHour: hour, minute: minute, second: 0, of: candidate
            ), time > reference {
                let weekday = calendar.component(.weekday, from: time)
                if days == nil || days!.contains(weekday) { return time }
            }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = tomorrow
        }
        return nil
    }
}

extension AgentSchedule.Cadence {
    /// How it reads in a list.
    var description: String {
        switch self {
        case .everyMinutes(let minutes):
            return String(format: Strings.text(.scheduleEveryMinutesFormat), "\(minutes)")
        case .daily(let hour, let minute):
            return String(format: Strings.text(.scheduleDailyFormat), Self.time(hour, minute))
        case .weekly(let days, let hour, let minute):
            let names = days.sorted().map { Self.weekdayName($0) }.joined(separator: ", ")
            return String(format: Strings.text(.scheduleWeeklyFormat), names, Self.time(hour, minute))
        }
    }

    private static func time(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// `Calendar`'s numbering, 1 = Sunday.
    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return "?" }
        return symbols[weekday - 1]
    }
}
