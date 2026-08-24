//
//  VoiceListenTests.swift
//  PuckTests
//
//  The chat window's mic button. PuckClient has no microphone, no recogniser
//  and no permission for either -- pet-app has all three -- so the button is
//  a request over the socket for the same push-to-talk the hotkey drives.
//

import XCTest
@testable import Puck

final class VoiceListenTests: XCTestCase {
    private func roundTrip(_ message: BridgeMessage) throws -> BridgeMessage {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(BridgeMessage.self, from: data)
    }

    func test_voiceListen_survivesTheWire() throws {
        XCTAssertEqual(try roundTrip(.voiceListen(true)), .voiceListen(true))
        XCTAssertEqual(try roundTrip(.voiceListen(false)), .voiceListen(false))
    }

    func test_voiceListen_isNamedInSnakeCaseLikeEveryOtherMessage() throws {
        let json = String(decoding: try JSONEncoder().encode(BridgeMessage.voiceListen(true)), as: UTF8.self)

        XCTAssertTrue(json.contains("\"voice_listen\""), json)
    }

    /// pet-app is the other end of this exchange, not a relay for it: the
    /// message is read where it lands.
    func test_voiceListen_isNotRelayedOnward() {
        XCTAssertNil(ClientRelay.targetRole(for: .voiceListen(true)))
    }

    /// The router is what turns it into a key-down, so a message that reached
    /// the router and fired nothing would be a mic button that does nothing.
    func test_theRouter_reportsBothEdges() {
        let router = BridgeMessageRouter(toolExecutor: ToolExecutor())
        var seen: [Bool] = []
        let bothSeen = expectation(description: "both edges delivered")
        router.onVoiceListen = { listening in
            seen.append(listening)
            if seen.count == 2 { bothSeen.fulfill() }
        }

        router.handle(.voiceListen(true), reply: { _ in })
        router.handle(.voiceListen(false), reply: { _ in })

        wait(for: [bothSeen], timeout: 2)
        XCTAssertEqual(seen, [true, false])
    }
    /// pet-app's answer, which is not always the request: the press that
    /// finds no speech-recognition permission is spent on the system prompt
    /// and records nothing. The chat window's button follows this, not its
    /// own click.
    func test_voiceListening_survivesTheWire() throws {
        XCTAssertEqual(try roundTrip(.voiceListening(true)), .voiceListening(true))
        XCTAssertEqual(try roundTrip(.voiceListening(false)), .voiceListening(false))
    }

    /// It goes to the window that asked, which is the gui role.
    func test_voiceListening_isRelayedToTheClient() {
        XCTAssertEqual(ClientRelay.targetRole(for: .voiceListening(true)), .gui)
    }

    /// The request and the answer are different messages, so a client cannot
    /// mistake its own ask coming back for pet-app agreeing to it.
    func test_theRequestAndTheAnswerAreNamedApart() throws {
        let request = String(decoding: try JSONEncoder().encode(BridgeMessage.voiceListen(true)), as: UTF8.self)
        let answer = String(decoding: try JSONEncoder().encode(BridgeMessage.voiceListening(true)), as: UTF8.self)

        XCTAssertNotEqual(request, answer)
        XCTAssertTrue(answer.contains("voice_listening"), answer)
    }
}
