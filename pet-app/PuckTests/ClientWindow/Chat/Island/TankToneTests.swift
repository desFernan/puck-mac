//
//  TankToneTests.swift
//  PuckTests
//
//  The folded band takes its colours from the picture the open island is
//  filled with, and anyone may replace that picture.
//

import XCTest
import SwiftUI
@testable import Puck

final class TankToneTests: XCTestCase {
    private func sample(_ red: Double, _ green: Double, _ blue: Double) -> TankSample {
        TankSample(red: red, green: green, blue: blue)
    }

    /// Averaging is arithmetic, so a colour that went through it comes back a
    /// few bits off the one that went in.
    private func assertSample(
        _ read: TankSample?,
        _ expected: TankSample,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let read = try? XCTUnwrap(read, message, file: file, line: line)
        guard let read else { return }
        XCTAssertEqual(read.red, expected.red, accuracy: 0.0001, message, file: file, line: line)
        XCTAssertEqual(read.green, expected.green, accuracy: 0.0001, message, file: file, line: line)
        XCTAssertEqual(read.blue, expected.blue, accuracy: 0.0001, message, file: file, line: line)
    }

    /// A picture laid out like the shipped one: water on top, sand at the
    /// bottom. Ten rows, four columns.
    private func scene(water: TankSample, floor: TankSample) -> [[TankSample]] {
        (0..<10).map { row in
            Array(repeating: row < TankToneReader.waterRows ? water : floor, count: 4)
        }
    }

    /// The whole point of reading the picture: change the picture, change the
    /// band.
    func testTheToneFollowsThePicture() {
        let green = tone(of: scene(water: sample(0.1, 0.8, 0.4), floor: sample(0.9, 0.85, 0.6)))
        let red = tone(of: scene(water: sample(0.8, 0.2, 0.2), floor: sample(0.9, 0.85, 0.6)))

        XCTAssertNotEqual(green, red)
        assertSample(green.depth[1], sample(0.1, 0.8, 0.4))
        assertSample(red.depth[1], sample(0.8, 0.2, 0.2))
    }

    /// The band shows water. The sand at the bottom of the picture is a
    /// different colour family altogether, and averaging it in turns the
    /// water beige.
    func testTheFloorIsNotAveragedIntoTheWater() {
        let water = sample(0.1, 0.5, 0.9)
        let read = tone(of: scene(water: water, floor: sample(0.95, 0.9, 0.7)))

        assertSample(read.depth[1], water, "the seabed leaked into the water")
        for current in read.currents {
            assertSample(current, water)
        }
    }

    /// One current per column of the picture, so a band drawn from them
    /// varies along its length the way the picture does.
    func testThereIsOneCurrentPerColumn() {
        let columns = (0..<10).map { row in
            (0..<4).map { column in sample(Double(column) / 4, 0.5, 0.9) }
        }

        XCTAssertEqual(tone(of: columns).currents.count, 4)
        for (read, expected) in zip(tone(of: columns).currents.map(\.red), [0, 0.25, 0.5, 0.75]) {
            XCTAssertEqual(read, expected, accuracy: 0.0001)
        }
    }

    /// A drawn scene's water is very nearly one colour all the way down, so
    /// three rows of it make a flat bar. The depth is put there instead, on
    /// the colour the picture gave.
    func testTheDepthIsLitAtTheTopAndDarkAtTheBottom() {
        let flat = sample(0.4, 0.7, 0.9)
        let depth = tone(of: scene(water: flat, floor: sample(0.9, 0.85, 0.6))).depth

        XCTAssertEqual(depth.count, 3)
        assertSample(depth[1], flat, "the middle is the picture's own colour")
        XCTAssertGreaterThan(depth[0].blue, depth[1].blue, "lit at the surface")
        XCTAssertLessThan(depth[2].blue, depth[1].blue, "and unlit at the floor")
        // Still the same colour, not a wash to white and black.
        XCTAssertGreaterThan(depth[0].blue - depth[0].red, 0.2)
        XCTAssertGreaterThan(depth[2].blue - depth[2].red, 0.2)
    }

    /// A picture that reads as nothing is a picture somebody will replace.
    /// Until they do, the island looks like itself rather than like a black
    /// bar.
    func testAnUnreadablePictureFallsBackRatherThanGoingDark() {
        XCTAssertEqual(TankToneReader.tone(fromGrid: []), .fallback)
        XCTAssertEqual(TankToneReader.tone(fromGrid: [[], [], []]), .fallback)
        XCTAssertEqual(TankToneReader.tone(fromGrid: Array(repeating: [], count: 10)), .fallback)
    }

    /// The wash lets the depth show between the picture's columns; running
    /// one column straight into the next is a single flat colour, because
    /// column averages of one scene are close together by nature.
    func testTheWashLetsTheDepthShowBetweenColumns() {
        let wash = PetTankView.currentWash([
            sample(1, 0, 0), sample(0, 1, 0), sample(0, 0, 1), sample(1, 1, 0),
        ])

        XCTAssertEqual(wash.count, 4)
        XCTAssertEqual(wash[1], .clear)
        XCTAssertEqual(wash[3], .clear)
        XCTAssertNotEqual(wash[0], .clear)
        XCTAssertNotEqual(wash[2], .clear)
    }

    func testAnEmptyWashIsClearRatherThanAnEmptyGradient() {
        XCTAssertEqual(PetTankView.currentWash([]), [.clear])
    }

    private func tone(of grid: [[TankSample]]) -> TankTone {
        TankToneReader.tone(fromGrid: grid)
    }
}
