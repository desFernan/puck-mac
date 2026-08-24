//
//  PetHomeDeciderTests.swift
//  Puck
//
//  The one place that decides whether the pet is in its tank. Kept pure so
//  the priority order and the debounce can be tested without a socket.
//

import XCTest
@testable import Puck

final class PetHomeDeciderTests: XCTestCase {
    private func settled(_ decider: PetHomeDecider) -> PetHomeDecider.Move? {
        // One second of frames at 60fps: past the 0.7s hold.
        var move: PetHomeDecider.Move?
        for _ in 0..<60 { move = decider.tick(dt: 1.0 / 60) ?? move }
        return move
    }

    func test_aVisibleTankOnAFrontmostWindow_bringsThePetHome() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)

        XCTAssertEqual(settled(decider), .home)
    }

    /// Picking the pet up puts it under somebody else's control. Whatever
    /// the desktop does while it is held -- a window closing, the chat
    /// window losing front -- must not pull it out of the hand holding it.
    func test_nothingMovesThePetWhileItIsHeld() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)
        XCTAssertEqual(settled(decider), .home)

        decider.isBeingHeld = true
        decider.report(hasTank: true, visible: false)

        XCTAssertNil(settled(decider), "the pet stays where the hand put it")
    }

    /// Letting go decides again from what was reported meanwhile, rather than
    /// waiting for the next change -- which may never come.
    func test_lettingGoAppliesWhatWasReportedDuringTheDrag() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)
        XCTAssertEqual(settled(decider), .home)

        decider.isBeingHeld = true
        decider.report(hasTank: true, visible: false)
        _ = settled(decider)
        decider.isBeingHeld = false

        XCTAssertEqual(settled(decider), .desktop)
    }

    /// The window going to the back is the ordinary way the pet leaves.
    func test_theWindowLosingFront_sendsThePetOut() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)
        _ = settled(decider)

        decider.report(hasTank: true, visible: false)

        XCTAssertEqual(settled(decider), .desktop)
    }

    /// Alt-tabbing past the window should not teleport the pet twice.
    func test_aStateThatDoesNotHold_isNotActedOn() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)

        // Measured against the hold rather than in fixed frames: how long a
        // state has to last before the pet acts on it is a number that gets
        // tuned, and a test with 20 frames written into it starts failing for
        // a reason that has nothing to do with what it is checking.
        let tooShort = PetHomeDecider.holdSeconds * 0.6

        var move: PetHomeDecider.Move?
        for _ in 0..<Int(tooShort * 60) { move = decider.tick(dt: 1.0 / 60) ?? move }
        XCTAssertNil(move, "not held long enough yet")

        decider.report(hasTank: true, visible: false)
        for _ in 0..<Int(tooShort * 60) { move = decider.tick(dt: 1.0 / 60) ?? move }
        XCTAssertNil(move, "the new state has not held either")
    }

    /// Looking away sends it back out. There is no pin any more: the pet is
    /// home while there is a tank and the user is looking at it.
    func test_theWindowGoingBehindSendsThePetToTheDesktop() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)
        XCTAssertEqual(settled(decider), .home)

        decider.report(hasTank: true, visible: false)

        XCTAssertEqual(settled(decider), .desktop)
    }

    /// A pet in a tank nobody can see is indistinguishable from a pet that
    /// has vanished.
    func test_losingTheTankSendsThePetOut() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)
        _ = settled(decider)

        decider.report(hasTank: false, visible: false)

        XCTAssertEqual(settled(decider), .desktop)
    }

    /// Hiding the pet from the menu bar wins over everything: the answer to
    /// "where is the pet" is "nowhere" until it is shown again.
    func test_aHiddenPetIsNotMovedAtAll() {
        let decider = PetHomeDecider()
        decider.isPetHidden = true
        decider.report(hasTank: true, visible: true)

        XCTAssertNil(settled(decider))
    }

    /// Nothing is emitted for a state the pet is already in -- the frame loop
    /// asks every frame and must not be told to move sixty times a second.
    func test_theSameStateIsReportedOnce() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)
        XCTAssertEqual(settled(decider), .home)

        XCTAssertNil(settled(decider))
    }

    /// A live client reports on every layout pass, so the same answer arrives
    /// again and again while the pet is still waiting out the hold. If that
    /// restarted the timer, the pet would never move at all.
    func test_repeatingTheSameReportDoesNotRestartTheHold() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)

        var move: PetHomeDecider.Move?
        for _ in 0..<60 {
            decider.report(hasTank: true, visible: true)
            move = decider.tick(dt: 1.0 / 60) ?? move
        }

        XCTAssertEqual(move, .home)
    }

    /// Showing the pet again has to re-decide from what the client last said.
    /// Nothing will arrive to prompt it: the client sends only on a change,
    /// and hiding the pet is not one.
    func test_showingThePetAgainActsOnTheLastReport() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)
        decider.isPetHidden = true
        XCTAssertNil(settled(decider), "nothing moves while hidden")

        decider.isPetHidden = false

        XCTAssertEqual(settled(decider), .home)
    }

    /// A code tour sends the pet out at once -- it points at things below the
    /// tank -- and the run ending is what lets it back in. Nothing new is
    /// reported in between, so the move must not need one.
    func test_aTourSendsThePetOutAndTheRunEndingBringsItBack() {
        let decider = PetHomeDecider()
        decider.report(hasTank: true, visible: true)
        XCTAssertEqual(settled(decider), .home)

        decider.forceDesktop()
        XCTAssertEqual(decider.tick(dt: 1.0 / 60), .desktop, "no hold to wait out")
        for _ in 0..<120 { XCTAssertNil(decider.tick(dt: 1.0 / 60), "and nothing pulls it back on its own") }

        decider.resumeReportedState()

        XCTAssertEqual(settled(decider), .home)
    }
}
