//
//  ClientWindowStoreSnapshotTests.swift
//  PuckTests
//
//  The copy of the workspace list that threads other than the main one read.
//

import XCTest
@testable import Puck

final class ClientWindowStoreSnapshotTests: XCTestCase {
    private func makeStore() -> ClientWindowStore {
        ClientWindowStore(sender: UserInputSender(transport: { nil }))
    }

    /// Built in `init`, where a `didSet` does not run: without an explicit
    /// first build the snapshot would be empty until something changed.
    func testTheDefaultWorkspaceIsThereFromTheStart() {
        let store = makeStore()

        XCTAssertEqual(
            store.workspaceSnapshot(ClientWindowStore.defaultWorkspaceId)?.id,
            ClientWindowStore.defaultWorkspaceId
        )
    }

    func testItFollowsWorkspacesAsTheyArrive() {
        let store = makeStore()
        XCTAssertNil(store.workspaceSnapshot("w2"))

        store.handleClientUpdate(
            .workspaceCreate(workspaceId: "w2", name: "Tank Test", projectPath: "/tmp/tank")
        )

        XCTAssertEqual(store.workspaceSnapshot("w2")?.projectPath, "/tmp/tank")
        XCTAssertEqual(store.workspaceSnapshot("w2")?.name, "Tank Test")
    }

    /// A run still asking about a workspace that has been deleted gets the
    /// honest answer rather than a stale one.
    func testADeletedWorkspaceIsGone() {
        let store = makeStore()
        store.handleClientUpdate(
            .workspaceCreate(workspaceId: "w2", name: "Tank Test", projectPath: "/tmp/tank")
        )
        XCTAssertNotNil(store.workspaceSnapshot("w2"))

        store.handleClientUpdate(.workspaceDelete(workspaceId: "w2"))

        XCTAssertNil(store.workspaceSnapshot("w2"))
    }
}
