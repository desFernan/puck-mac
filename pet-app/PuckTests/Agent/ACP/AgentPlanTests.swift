//
//  AgentPlanTests.swift
//  PuckTests
//
//  Reading the agent's plan off the wire, and what the transcript does with
//  one that keeps changing.
//

import XCTest
@testable import Puck

final class AgentPlanTests: XCTestCase {
    private func update(_ json: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func test_aPlanIsReadWithItsStepsInOrderAndTheirStates() throws {
        let plan = try XCTUnwrap(AgentPlan.from(update: update("""
        {"sessionUpdate":"plan","entries":[
          {"content":"테스트를 읽는다","status":"completed"},
          {"content":"원인을 찾는다","status":"in_progress"},
          {"content":"고친다","status":"pending"}
        ]}
        """)))

        XCTAssertEqual(plan.steps.map(\.text), ["테스트를 읽는다", "원인을 찾는다", "고친다"])
        XCTAssertEqual(plan.steps.map(\.status), [.completed, .inProgress, .pending])
        XCTAssertEqual(plan.completedCount, 1)
        XCTAssertEqual(plan.currentStep?.text, "원인을 찾는다")
    }

    /// The notification arrives wrapped; the mapping has to reach inside it
    /// the same way every other update does.
    func test_theWrappedFormTheNotificationActuallyArrivesInIsRead() throws {
        let plan = try XCTUnwrap(AgentPlan.from(update: update("""
        {"sessionId":"s-1","update":{"sessionUpdate":"plan","entries":[{"content":"하나","status":"pending"}]}}
        """)))

        XCTAssertEqual(plan.steps.count, 1)
    }

    /// A newer agent inventing a fourth state should cost the checklist one
    /// wrong tick, not the plan.
    func test_anUnknownStateIsTreatedAsNotStartedRatherThanRefused() throws {
        let plan = try XCTUnwrap(AgentPlan.from(update: update("""
        {"sessionUpdate":"plan","entries":[{"content":"하나","status":"deferred"}]}
        """)))

        XCTAssertEqual(plan.steps.first?.status, .pending)
    }

    func test_aPlanWithNothingInItIsNoPlanAtAll() {
        XCTAssertNil(AgentPlan.from(update: update("""
        {"sessionUpdate":"plan","entries":[]}
        """)))
        XCTAssertNil(AgentPlan.from(update: update("""
        {"sessionUpdate":"plan","entries":[{"content":"   ","status":"pending"}]}
        """)))
        XCTAssertNil(AgentPlan.from(update: update("{\"sessionUpdate\":\"plan\"}")))
    }

    /// Nothing is in progress yet, so the first thing not done is what is
    /// next.
    func test_beforeAnythingStartsTheFirstStepIsTheCurrentOne() throws {
        let plan = try XCTUnwrap(AgentPlan.from(update: update("""
        {"sessionUpdate":"plan","entries":[
          {"content":"하나","status":"pending"},{"content":"둘","status":"pending"}]}
        """)))

        XCTAssertEqual(plan.currentStep?.text, "하나")
    }

    /// It has to survive a restart with the rest of the transcript.
    func test_aPlanSurvivesBeingWrittenDown() throws {
        let original = AgentPlan(steps: [AgentPlanStep(text: "하나", status: .inProgress)])

        let restored = try JSONDecoder().decode(AgentPlan.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(restored, original)
    }
}

final class AcpPlanMappingTests: XCTestCase {
    /// The update the mapping used to drop on the floor.
    func test_aPlanUpdateBecomesAPlanEvent() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"update":{"sessionUpdate":"plan","entries":[{"content":"하나","status":"pending"}]}}
        """.utf8))

        let event = AcpEventMapping.event(for: AcpSessionUpdate(raw: raw), callID: "c-1")

        guard case .planUpdated(let plan)? = event else {
            return XCTFail("expected a plan event, got \(String(describing: event))")
        }
        XCTAssertEqual(plan.steps.first?.text, "하나")
    }

    /// An empty plan is the agent clearing what it said, and there is no row
    /// to draw for that.
    func test_anEmptyPlanUpdateIsStillNothing() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"update":{"sessionUpdate":"plan","entries":[]}}
        """.utf8))

        XCTAssertNil(AcpEventMapping.event(for: AcpSessionUpdate(raw: raw), callID: "c-1"))
    }

    /// The pet has nothing to do with a checklist in a window it is standing
    /// on.
    func test_thePetDoesNotReactToAPlan() {
        let reaction = EventRouter.reaction(for: .planUpdated(plan: AgentPlan(steps: [
            AgentPlanStep(text: "하나", status: .pending),
        ])))

        XCTAssertEqual(reaction, EventReaction())
    }

    /// It crosses the socket like every other event.
    func test_aPlanEventSurvivesTheWire() throws {
        let message = BridgeMessage.event(
            .planUpdated(plan: AgentPlan(steps: [AgentPlanStep(text: "하나", status: .completed)])),
            workspaceId: "w1",
            sessionId: "s1"
        )

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(BridgeMessage.self, from: encoded)

        XCTAssertEqual(decoded, message)
    }
}
