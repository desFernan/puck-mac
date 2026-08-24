//
//  WindowListWatcherTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Pure filtering logic: layer 0 only, exclude self, exclude below minimum size.
//  The live CGWindowListCopyWindowInfo fetch and NSWorkspace/Timer polling are
//  not unit tested here — they depend on real on-screen windows and OS timers.
//

import XCTest
import CoreGraphics
@testable import Puck

final class WindowListWatcherTests: XCTestCase {
    private func window(pid: pid_t = 100, layer: Int = 0, size: CGSize = CGSize(width: 200, height: 200)) -> WindowInfo {
        WindowInfo(
            windowID: 1, ownerPID: pid, ownerName: nil, title: nil, layer: layer,
            frame: CGRect(origin: .zero, size: size)
        )
    }

    func test_keepsNormalLayerWindow() {
        let result = WindowListWatcher.filter([window(layer: 0)], excludingPID: 999, minimumSize: CGSize(width: 40, height: 40))
        XCTAssertEqual(result.count, 1)
    }

    func test_excludesNonZeroLayerWindows() {
        let result = WindowListWatcher.filter([window(layer: 3)], excludingPID: 999, minimumSize: CGSize(width: 40, height: 40))
        XCTAssertTrue(result.isEmpty)
    }

    func test_excludesOwnProcessWindows() {
        let result = WindowListWatcher.filter([window(pid: 999)], excludingPID: 999, minimumSize: CGSize(width: 40, height: 40))
        XCTAssertTrue(result.isEmpty)
    }

    func test_excludesWindowsSmallerThanMinimumSize() {
        let tiny = window(size: CGSize(width: 10, height: 10))
        let result = WindowListWatcher.filter([tiny], excludingPID: 999, minimumSize: CGSize(width: 40, height: 40))
        XCTAssertTrue(result.isEmpty)
    }

    func test_preservesZOrder() {
        let front = window(pid: 1)
        let back = window(pid: 2)
        let result = WindowListWatcher.filter([front, back], excludingPID: 999, minimumSize: CGSize(width: 40, height: 40))
        XCTAssertEqual(result.map(\.ownerPID), [1, 2])
    }
}
