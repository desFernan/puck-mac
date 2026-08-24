//
//  RelativeTime.swift
//  Puck
//
//  Sidebar/tab timestamps. Port of chat-web's relative-time.ts, brought over
//  with the chat UI (2026-08-15) rather than reimplemented -- its rules are
//  the ones the sidebar was designed around.
//
//  Deliberately coarser than RelativeDateTimeFormatter: this is a glanceable
//  hint next to a session title, so "12m" beats "12 minutes ago", and
//  anything older than a week collapses to a date.
//
//  `now` is injected so it is testable without faking the clock -- the same
//  reason the TS version took it as a parameter.
//

import Foundation

enum RelativeTime {
    /// The language is taken as a parameter for the same reason `now` is:
    /// tests name the one they mean instead of following the machine.
    static func short(
        since date: Date?,
        now: Date = Date(),
        language: AppLanguage = Localization.shared.language
    ) -> String {
        func text(_ key: L10nKey, _ arguments: CVarArg...) -> String {
            String(format: Strings.text(key, language: language), arguments: arguments)
        }
        guard let date else { return "" }
        let seconds = now.timeIntervalSince(date)
        // A clock that moved backwards (NTP correction, timezone edit) must
        // not render a negative age.
        guard seconds >= 0 else { return text(.timeJustNow) }

        let minutes = Int(seconds / 60)
        if minutes < 1 { return text(.timeJustNow) }
        if minutes < 60 { return text(.timeMinutesFormat, "\(minutes)") }

        let hours = minutes / 60
        if hours < 24 { return text(.timeHoursFormat, "\(hours)") }

        let days = hours / 24
        if days == 1 { return text(.timeYesterday) }
        if days < 7 { return text(.timeDaysFormat, "\(days)") }

        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return "" }
        return text(.timeMonthDayFormat, "\(month)", "\(day)")
    }
}
