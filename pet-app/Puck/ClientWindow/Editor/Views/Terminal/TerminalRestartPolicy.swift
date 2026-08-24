//
//  TerminalRestartPolicy.swift
//  Puck
//
//  Whether a shell that exited should be replaced.
//
//  Pulled out of the view because it is the one part of the terminal with a
//  rule in it, and a rule inside a SwiftUI body is a rule nothing can check.
//  A shell someone worked in for an hour and then typed `exit` into should be
//  replaced; one that dies the instant it starts -- a broken `SHELL`, a
//  profile that calls `exit`, a project directory that has gone -- must not
//  be, or the pane forks shells as fast as the machine can until someone
//  closes it.
//

import Foundation

struct TerminalRestartPolicy {
    /// A shell that lasted less than this never really started.
    static let earlyExitSeconds: TimeInterval = 2
    /// How many of those in a row before the pane gives up and says so.
    static let earlyExitLimit = 3

    private(set) var consecutiveEarlyExits = 0
    private(set) var hasGivenUp = false

    enum Outcome: Equatable {
        case restart
        case giveUp
    }

    /// - Parameter lifetime: how long the shell that just exited was alive.
    mutating func shellExited(afterRunningFor lifetime: TimeInterval) -> Outcome {
        // Time, not a count of restarts: the run that lasted is what says the
        // shell works, and it is what resets the tally.
        if lifetime < Self.earlyExitSeconds {
            consecutiveEarlyExits += 1
        } else {
            consecutiveEarlyExits = 0
        }
        guard consecutiveEarlyExits < Self.earlyExitLimit else {
            hasGivenUp = true
            return .giveUp
        }
        return .restart
    }
}
