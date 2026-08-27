//
//  VoiceOverAnnouncer.swift
//  Puck
//
//  Saying out loud the two things that only ever happened on screen.
//
//  The pet talks in a bubble over its own head, and a run that needs
//  permission puts a banner in the transcript. Neither takes focus -- the
//  overlay is click-through by design, and the banner arrives while the caret
//  is still in the composer -- so VoiceOver has no reason to read either one.
//  From behind a screen reader the pet is mute and a run stops for no stated
//  reason and waits for an answer nobody knows it wants.
//
//  An announcement is AppKit's answer to exactly that shape: text spoken
//  once, where the user already is, without moving focus or stealing the
//  key window.
//

import AppKit

enum VoiceOverAnnouncer {
    /// Speaks `text`, if anything is listening.
    ///
    /// Nothing is listening most of the time, and that is fine: with no
    /// assistive client attached the notification is delivered to nobody and
    /// costs a dictionary. There is deliberately no "is VoiceOver running"
    /// check -- `NSWorkspace.isVoiceOverEnabled` answers for VoiceOver alone,
    /// and a switch-control or braille user asking the same question of the
    /// system would be told no.
    ///
    /// - Parameter priority: `.high` interrupts whatever is being spoken.
    ///   For the two callers here that is right for an approval (the run is
    ///   blocked until it is answered) and wrong for a passing remark.
    static func announce(_ text: String, priority: NSAccessibilityPriorityLevel = .medium) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: trimmed,
                .priority: priority.rawValue,
            ]
        )
    }
}
