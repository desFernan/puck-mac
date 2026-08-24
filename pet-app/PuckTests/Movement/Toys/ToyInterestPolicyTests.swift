//
//  ToyInterestPolicyTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Which of several toys the pet goes for next.
//

import XCTest
@testable import Puck

final class ToyInterestPolicyTests: XCTestCase {
    private func candidate(_ name: String, x: CGFloat, resting: Bool = true) -> ToyInterestPolicy.Candidate {
        ToyInterestPolicy.Candidate(name: name, position: CGPoint(x: x, y: 500), isResting: resting)
    }

    func test_noCandidates_picksNothing() {
        XCTAssertNil(ToyInterestPolicy.next(from: [], lastPlayed: nil, petPosition: .zero))
    }

    func test_ignoresToysThatArentRestingOnASurface() {
        // Mid-flight or in the user's hand: the pet has nothing to walk up to.
        let candidates = [candidate("pumpkin", x: 10, resting: false)]

        XCTAssertNil(ToyInterestPolicy.next(from: candidates, lastPlayed: nil, petPosition: .zero))
    }

    func test_picksTheNearestRestingToy() {
        let candidates = [candidate("pumpkin", x: 900), candidate("wand", x: 120)]

        let picked = ToyInterestPolicy.next(from: candidates, lastPlayed: nil, petPosition: CGPoint(x: 100, y: 500))

        XCTAssertEqual(picked, "wand")
    }

    /// The whole point of "부드럽게 섞이기": having just played with one toy,
    /// the pet moves on to another rather than looping on the same one.
    func test_skipsTheToyItJustPlayedWith_whenAnotherIsAvailable() {
        let candidates = [candidate("pumpkin", x: 100), candidate("wand", x: 900)]

        let picked = ToyInterestPolicy.next(
            from: candidates,
            lastPlayed: "pumpkin",
            petPosition: CGPoint(x: 100, y: 500)
        )

        // The pumpkin is right under its feet and it still goes for the wand.
        XCTAssertEqual(picked, "wand")
    }

    /// One toy out means there is nothing to move on to, so it stays playable
    /// -- this is the single-toy behaviour that shipped, and it must not
    /// regress into the pet refusing to play with its only toy.
    func test_repeatsTheSameToy_whenItIsTheOnlyOneOut() {
        let candidates = [candidate("pumpkin", x: 100)]

        let picked = ToyInterestPolicy.next(from: candidates, lastPlayed: "pumpkin", petPosition: .zero)

        XCTAssertEqual(picked, "pumpkin")
    }

    func test_skippingOnlyAppliesToRestingAlternatives() {
        // The wand is in the air, so it is not a real alternative and the
        // pumpkin stays the answer despite having just been played with.
        let candidates = [candidate("pumpkin", x: 100), candidate("wand", x: 200, resting: false)]

        let picked = ToyInterestPolicy.next(from: candidates, lastPlayed: "pumpkin", petPosition: .zero)

        XCTAssertEqual(picked, "pumpkin")
    }

    func test_equallyCloseToys_resolveInCatalogueOrder() {
        // Deterministic rather than arbitrary: two toys the same distance away
        // must not make the pet's choice flip frame to frame.
        let candidates = [candidate("pumpkin", x: 50), candidate("wand", x: 150)]

        let picked = ToyInterestPolicy.next(from: candidates, lastPlayed: nil, petPosition: CGPoint(x: 100, y: 500))

        XCTAssertEqual(picked, "pumpkin")
    }
}
