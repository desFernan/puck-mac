//
//  WorkspaceDeletionTests.swift
//  PuckTests
//
//  Throwing a workspace away. The registry is pet-app's, so the window asks
//  and applies what comes back -- and what comes back is the confirmation
//  that it happened, not an echo of the ask.
//

import XCTest
@testable import Puck

@MainActor
final class WorkspaceDeletionTests: XCTestCase {
    private func makeStore() -> ClientWindowStore {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        store.handleClientUpdate(.workspaceCreate(workspaceId: "w1", name: "Tank Test", projectPath: nil))
        return store
    }

    func test_theDefaultWorkspaceCannotBeDeleted() {
        let store = makeStore()

        XCTAssertFalse(store.canDeleteWorkspace(ClientWindowStore.defaultWorkspaceId))
        XCTAssertFalse(store.requestWorkspaceDeletion(workspaceId: ClientWindowStore.defaultWorkspaceId))
    }

    func test_oneThatIsNotThereCannotBeDeletedEither() {
        let store = makeStore()

        XCTAssertFalse(store.canDeleteWorkspace("never-existed"))
    }

    func test_aProjectWorkspaceCanBe() {
        let store = makeStore()

        XCTAssertTrue(store.canDeleteWorkspace("w1"))
    }

    /// Asking is not deleting: the row stays until pet-app says it is gone.
    func test_askingLeavesTheSidebarAlone() {
        let store = makeStore()

        store.requestWorkspaceDeletion(workspaceId: "w1")

        XCTAssertTrue(store.workspaces.contains { $0.id == "w1" })
    }

    func test_theConfirmationTakesTheWorkspaceAndItsChats() {
        let store = makeStore()
        store.handleClientUpdate(.sessionCreate(workspaceId: "w1", sessionId: "s1", title: "새 대화", origin: .user))

        store.applyWorkspaceDeletion(workspaceId: "w1")

        XCTAssertFalse(store.workspaces.contains { $0.id == "w1" })
        XCTAssertTrue(store.sessions(in: "w1").isEmpty)
        XCTAssertNil(store.session(workspaceId: "w1", sessionId: "s1"))
    }

    /// Deleting the workspace you are standing in has to leave you somewhere,
    /// and the default one is the place that cannot be deleted.
    func test_deletingTheActiveWorkspaceMovesYouHome() {
        let store = makeStore()
        store.selectSession(workspaceId: "w1", sessionId: ClientWindowStore.defaultSessionId)

        store.applyWorkspaceDeletion(workspaceId: "w1")

        XCTAssertEqual(store.activeWorkspaceId, ClientWindowStore.defaultWorkspaceId)
        XCTAssertEqual(store.activeSessionId, ClientWindowStore.defaultSessionId)
        XCTAssertNotNil(store.session(workspaceId: store.activeWorkspaceId, sessionId: store.activeSessionId))
    }

    /// A confirmation for something already gone is not an error: pet-app
    /// replays its registry on reconnect.
    func test_aRepeatedConfirmationIsHarmless() {
        let store = makeStore()
        store.applyWorkspaceDeletion(workspaceId: "w1")

        store.applyWorkspaceDeletion(workspaceId: "w1")

        XCTAssertFalse(store.workspaces.contains { $0.id == "w1" })
    }
}
