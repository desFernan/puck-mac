//
//  HeldOnce.swift
//  Puck
//
//  A value worked out on first use and kept for the life of the process.
//
//  Two places had written this out by hand -- the island's picture and the
//  colours read out of it -- and each came with its own lock, its own
//  `nonisolated(unsafe) static var` and its own comment explaining why that
//  was safe. Both are asked for on every frame a pet walks across the island,
//  which is what stops them being computed on demand; neither is asked for
//  before there is a screen, which is what stops them being global constants.
//
//  A failure is not kept. The picture comes out of a folder people drop their
//  own into, and remembering "there wasn't one" would mean a bad read at
//  launch is a blank island until the app is quit.
//
//  `@unchecked Sendable`: `held` is reached from whatever context SwiftUI
//  evaluates a view in, and every access goes through `lock`.
//

import Foundation

final class HeldOnce<Value>: @unchecked Sendable {
    private let make: () -> Value?
    private var held: Value?
    private let lock = NSLock()

    init(_ make: @escaping () -> Value?) {
        self.make = make
    }

    /// The value, working it out if this is the first ask.
    ///
    /// `make` runs outside the lock. Holding a lock across a caller's own
    /// code is how two of these waiting on each other becomes a deadlock, and
    /// the cost of that is that a first ask from two threads at once may do
    /// the work twice -- which for reading a file is waste, not a bug. The
    /// first answer to arrive is the one everybody gets.
    func callAsFunction() -> Value? {
        lock.lock()
        let existing = held
        lock.unlock()
        if let existing { return existing }

        guard let made = make() else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if let raced = held { return raced }
        held = made
        return made
    }
}
