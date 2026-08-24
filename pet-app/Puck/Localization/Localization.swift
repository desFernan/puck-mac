//
//  Localization.swift
//  Puck
//
//  Holds the selected AppLanguage for the running process, and is the object
//  views watch so a language change redraws them instead of waiting for a
//  relaunch.
//
//  Each process keeps its own copy. Puck writes the setting and broadcasts
//  it; PuckClient seeds from Puck's defaults domain at launch and follows the
//  broadcast after that. Neither reads the other's UserDefaults on the hot
//  path, so `Strings.text(_:)` stays a dictionary lookup.
//

import Combine
import Foundation

final class Localization: ObservableObject, @unchecked Sendable {
    /// The instance `Strings.text(_:)` reads. Tests construct their own
    /// rather than mutating this one.
    static let shared = Localization()

    /// A serial queue rather than a lock: `Strings.text(_:)` is called from
    /// whichever queue is formatting a bubble or a tool summary, not only the
    /// main one, and a lock taken from an async context is an error in the
    /// Swift 6 language mode this project is heading for. Same choice, same
    /// reason, as LoopbackHTTPServer's state queue.
    private let queue = DispatchQueue(label: "Puck.Localization")
    private var storedLanguage: AppLanguage

    init(language: AppLanguage = .systemDefault) {
        storedLanguage = language
    }

    var language: AppLanguage {
        queue.sync { storedLanguage }
    }

    /// No-ops when the language is already the one asked for, so a broadcast
    /// that arrives twice does not redraw every window twice.
    func apply(_ language: AppLanguage) {
        let changed = queue.sync { () -> Bool in
            guard storedLanguage != language else { return false }
            storedLanguage = language
            return true
        }
        guard changed else { return }
        notifyViews()
    }

    /// SwiftUI only tolerates `objectWillChange` from the main actor, and the
    /// caller here may be any queue -- a broadcast handler, a settings write.
    private func notifyViews() {
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            // `self`, not the publisher: this type is Sendable (its state is
            // behind `queue`) and Combine's publisher is not, so capturing
            // the object is the one of the two that can honestly cross.
            DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
        }
    }
}
