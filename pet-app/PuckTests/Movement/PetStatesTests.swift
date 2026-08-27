//
//  PetStatesTests.swift
//  PuckTests
//
//  Every state the pet can be asked to be in has an instance behind it.
//
//  A StateKind nobody put in the table is not a build error. It is a line in
//  the log at the moment somebody transitions to it -- and what the user sees
//  is the pet not reacting, which looks like the event never arrived.
//

import XCTest
@testable import Puck

@MainActor
final class PetStatesTests: XCTestCase {
    func test_everyStateKindHasAnInstance() {
        let table = PetStates().byKind

        for kind in StateKind.allCases {
            XCTAssertNotNil(table[kind], "\(kind) has nothing to transition to")
        }
    }

    /// Not just present -- distinct. A table with two kinds pointing at one
    /// instance passes a count and still plays the wrong clip.
    func test_noTwoKindsShareAnInstance() {
        let table = PetStates().byKind

        let instances = Set(table.values.map(ObjectIdentifier.init))
        XCTAssertEqual(instances.count, table.count)
    }

    /// The registry is what the controller is built from, so a kind it holds
    /// and does not hand over is a transition that logs and does nothing.
    func test_registeringHandsOverEveryKind() {
        let states = PetStates()
        let controller = CharacterController(
            initialState: states.idle,
            body: CharacterBody(avatar: SpyAvatarPlayable(), position: .zero),
            sfxPlayer: SpySFXTriggering()
        )

        states.register(in: controller)

        for kind in StateKind.allCases {
            controller.transition(to: kind)
            XCTAssertTrue(
                controller.currentState === states.byKind[kind],
                "\(kind) did not become the state registered for it"
            )
        }
    }

    /// One instance per state, reused: CharacterController's same-state
    /// no-op guard is reference equality, and a fresh instance per
    /// transition silently defeats it -- which reset Idle's wander timer and
    /// replayed its clip on every repeated event.
    func test_theSameInstanceComesBackEveryTime() {
        let states = PetStates()

        XCTAssertTrue(states.idle === states.idle)
        XCTAssertTrue(states.byKind[.idle] === states.byKind[.idle])
    }
}
