//
//  FileDescriptorLimitTests.swift
//  PuckTests
//
//  How many files this process may hold open, and everything it spawns with
//  it.
//
//  The reported fault was the coding agent dying on its own configuration
//  file -- "EMFILE: too many open files, watch ~/.claude/settings.json" --
//  which is launchd's soft limit of 256 inherited all the way down.
//

import XCTest
@testable import Puck

final class FileDescriptorLimitTests: XCTestCase {
    /// The case that matters: a GUI app started by launchd, whose hard limit
    /// is unlimited and whose real ceiling is the kernel's.
    func test_aLaunchdChildIsRaisedToTheKernelsCeiling() {
        let target = FileDescriptorLimit.target(
            current: 256,
            hard: rlim_t.max,
            kernelMaximum: 92_160
        )

        XCTAssertEqual(target, 92_160)
    }

    /// A hard limit below the kernel's cap is the real one -- asking past it
    /// fails outright, and a failed raise leaves the process at 256.
    func test_aHardLimitBelowTheKernelsCapIsWhatIsAskedFor() {
        let target = FileDescriptorLimit.target(
            current: 256,
            hard: 4_096,
            kernelMaximum: 92_160
        )

        XCTAssertEqual(target, 4_096)
    }

    /// Nothing to do is answered with nothing, so a shell-launched build does
    /// not spend a syscall lowering its own limit.
    func test_aProcessThatAlreadyHasEnoughIsLeftAlone() {
        XCTAssertNil(FileDescriptorLimit.target(current: 1_048_576, hard: rlim_t.max, kernelMaximum: 92_160))
        XCTAssertNil(FileDescriptorLimit.target(current: 92_160, hard: rlim_t.max, kernelMaximum: 92_160))
    }

    /// The limit is never lowered. A machine whose kernel cap is somehow
    /// under the current soft limit must be left as it is rather than
    /// "raised" downward.
    func test_theLimitIsNeverLowered() {
        XCTAssertNil(FileDescriptorLimit.target(current: 10_000, hard: rlim_t.max, kernelMaximum: 4_096))
    }

    /// And the real one: whatever this machine reports has to be a number a
    /// process could actually be given.
    func test_theKernelsCapIsReadable() {
        XCTAssertGreaterThanOrEqual(FileDescriptorLimit.kernelMaximumFilesPerProcess(), 256)
    }
}
