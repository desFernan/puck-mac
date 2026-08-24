//
//  VoiceInputControllerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Hold-duration gating (plan/02_pet-app.md F7: "홀드 0.3초 미만 무시, 마이크
//  점유는 홀드 구간 한정") and Listen state lifecycle, tested against a fake
//  SpeechRecognitionServicing + an injected clock (no real mic/Speech
//  framework needed).
//

import XCTest
@testable import Puck

private final class FakeSpeechRecognitionService: SpeechRecognitionServicing {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func startStreaming() { startCallCount += 1 }
    func stopStreaming() { stopCallCount += 1 }
}

private struct FakeError: Error {}

final class VoiceInputControllerTests: XCTestCase {
    func test_pushToTalkDown_startsListeningAndStreaming() {
        let speech = FakeSpeechRecognitionService()
        var listenStarted = false
        let controller = VoiceInputController(speechService: speech, now: { 0 }, hasVoicePermissions: { true })
        controller.onListenStart = { listenStarted = true }

        controller.pushToTalkDown()

        XCTAssertTrue(listenStarted)
        XCTAssertEqual(speech.startCallCount, 1)
    }

    func test_pushToTalkUp_alwaysStopsStreamingAndEndsListen_regardlessOfDuration() {
        let speech = FakeSpeechRecognitionService()
        var listenEnded = false
        var uptime: TimeInterval = 0
        let controller = VoiceInputController(speechService: speech, now: { uptime }, hasVoicePermissions: { true })
        controller.onListenEnd = { listenEnded = true }

        controller.pushToTalkDown()
        uptime = 0.1 // held for only 0.1s -- shorter than the 0.3s minimum
        controller.pushToTalkUp()

        XCTAssertEqual(speech.stopCallCount, 1)
        XCTAssertTrue(listenEnded)
    }

    func test_pushToTalkDown_whileAlreadyActive_doesNotResetHoldStartTime() {
        // Defense in depth alongside HotkeyDecisionMaker's key-repeat guard --
        // a duplicate down signal while already active must not slide the
        // hold-start time forward or restart streaming.
        let speech = FakeSpeechRecognitionService()
        var uptime: TimeInterval = 0
        let controller = VoiceInputController(speechService: speech, now: { uptime }, hasVoicePermissions: { true })
        var receivedFinal: String?
        controller.onFinalText = { receivedFinal = $0 }

        controller.pushToTalkDown()
        uptime = 0.2
        controller.pushToTalkDown() // duplicate/repeat signal while still active
        uptime = 0.4 // 0.4s since the FIRST down -- over the 0.3s minimum
        controller.pushToTalkUp()

        speech.onFinalResult?("held long enough")

        XCTAssertEqual(receivedFinal, "held long enough")
        XCTAssertEqual(speech.startCallCount, 1)
    }

    func test_finalResult_isIgnored_whenHeldShorterThanMinimum() {
        let speech = FakeSpeechRecognitionService()
        var uptime: TimeInterval = 0
        let controller = VoiceInputController(speechService: speech, now: { uptime }, hasVoicePermissions: { true })
        var receivedFinal: String?
        controller.onFinalText = { receivedFinal = $0 }

        controller.pushToTalkDown()
        uptime = 0.1 // under VoiceInputController.minimumHoldDuration (0.3s)
        controller.pushToTalkUp()

        speech.onFinalResult?("accidental tap")

        XCTAssertNil(receivedFinal)
    }

    func test_finalResult_isDelivered_whenHeldLongEnough() {
        let speech = FakeSpeechRecognitionService()
        var uptime: TimeInterval = 0
        let controller = VoiceInputController(speechService: speech, now: { uptime }, hasVoicePermissions: { true })
        var receivedFinal: String?
        controller.onFinalText = { receivedFinal = $0 }

        controller.pushToTalkDown()
        uptime = 1.0 // well over the 0.3s minimum
        controller.pushToTalkUp()

        speech.onFinalResult?("테스트 돌려줘")

        XCTAssertEqual(receivedFinal, "테스트 돌려줘")
    }

    func test_speechServiceError_forwardsErrorAndEndsListen_soFSMDoesntGetStuck() {
        // Previously dropped silently -- if startStreaming() failed (e.g.
        // recognizer unavailable), onListenStart already fired unconditionally
        // and nothing ever reverted it without a manual key release.
        let speech = FakeSpeechRecognitionService()
        let controller = VoiceInputController(speechService: speech, now: { 0 }, hasVoicePermissions: { true })
        var receivedError: Error?
        var listenEnded = false
        controller.onError = { receivedError = $0 }
        controller.onListenEnd = { listenEnded = true }

        controller.pushToTalkDown()
        speech.onError?(FakeError())

        XCTAssertNotNil(receivedError)
        XCTAssertTrue(listenEnded)
    }

    func test_partialResults_areAlwaysForwarded_regardlessOfDuration() {
        // Partial results are just live captions while holding -- not gated
        // by the eventual hold-duration check (that only applies to the
        // final, submitted text).
        let speech = FakeSpeechRecognitionService()
        let uptime: TimeInterval = 0
        let controller = VoiceInputController(speechService: speech, now: { uptime }, hasVoicePermissions: { true })
        var receivedPartial: String?
        controller.onPartialText = { receivedPartial = $0 }

        controller.pushToTalkDown()
        speech.onPartialResult?("테스")

        XCTAssertEqual(receivedPartial, "테스")
    }

    /// The first hold asks for the microphone instead of recording into one
    /// it does not have. Asking at launch instead is what put a system dialog
    /// on the desktop after every rebuild.
    func test_theFirstHoldWithoutPermissionAsksInsteadOfRecording() {
        let speech = FakeSpeechRecognitionService()
        var asked = 0
        let controller = VoiceInputController(
            speechService: speech,
            now: { 0 },
            hasVoicePermissions: { false },
            requestVoicePermissions: { asked += 1 }
        )

        controller.pushToTalkDown()

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(speech.startCallCount, 0, "nothing is recorded until the answer is yes")
    }

    /// And it asks once. A prompt cannot be answered while the key is held,
    /// so a second hold that re-asked would stack dialogs on someone who has
    /// already said no.
    func test_itAsksOnlyOnce() {
        let speech = FakeSpeechRecognitionService()
        var asked = 0
        let controller = VoiceInputController(
            speechService: speech,
            now: { 0 },
            hasVoicePermissions: { false },
            requestVoicePermissions: { asked += 1 }
        )

        controller.pushToTalkDown()
        controller.pushToTalkUp()
        controller.pushToTalkDown()

        XCTAssertEqual(asked, 1)
    }

    /// Once granted, holding records as it always did -- the check is not a
    /// gate that stays shut after the first refusal.
    func test_holdingAfterPermissionIsGrantedRecords() {
        let speech = FakeSpeechRecognitionService()
        var granted = false
        let controller = VoiceInputController(
            speechService: speech,
            now: { 0 },
            hasVoicePermissions: { granted },
            requestVoicePermissions: { granted = true }
        )

        controller.pushToTalkDown()
        controller.pushToTalkUp()
        controller.pushToTalkDown()

        XCTAssertEqual(speech.startCallCount, 1)
    }
}
