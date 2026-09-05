//
//  AvatarLinesTests.swift
//  PuckTests
//
//  What this particular character says.
//
//  A package could already change how the pet looks and sounds; every
//  character ever installed still sulked about being muted in exactly the
//  same sentence.
//

import XCTest
@testable import Puck

final class AvatarLinesTests: XCTestCase {
    /// A package that carries none gets the app's own wording.
    func test_aPackageWithNoLinesUsesTheAppsOwn() {
        XCTAssertEqual(AvatarLines.none.text(.muted), Strings.text(.bubbleMutedComplaint))
        XCTAssertEqual(AvatarLines.none.text(.clientOffline), Strings.text(.bubbleClientOffline))
    }

    func test_aPackagesOwnLineWins() {
        let lines = AvatarLines.from(manifest: ["muted": "냥... 조용히 있을게"])

        XCTAssertEqual(lines.text(.muted), "냥... 조용히 있을게")
        XCTAssertEqual(lines.text(.clientOffline), Strings.text(.bubbleClientOffline),
                       "the ones it does not carry are still the app's")
    }

    /// An empty string in a manifest is somebody clearing a field, not
    /// somebody asking the pet to say nothing -- and an empty bubble looks
    /// broken rather than quiet.
    func test_aBlankLineFallsBackRatherThanSayingNothing() {
        XCTAssertEqual(AvatarLines.from(manifest: ["muted": ""]).text(.muted), Strings.text(.bubbleMutedComplaint))
        XCTAssertEqual(AvatarLines.from(manifest: ["muted": "   "]).text(.muted), Strings.text(.bubbleMutedComplaint))
    }

    /// A line that takes the run's own summary.
    func test_aLineCanWrapWhatThePetWasGoingToSay() {
        let lines = AvatarLines.from(manifest: ["runFinished": "다 했다냥! %1$@"])

        XCTAssertEqual(lines.text(.runFinished, "세 파일 고쳤어요"), "다 했다냥! 세 파일 고쳤어요")
    }

    /// And one that does not wrap it gets the summary itself, which is what
    /// the pet already said.
    func test_theDefaultForASummaryLineIsTheSummary() {
        XCTAssertEqual(AvatarLines.none.text(.runFinished, "끝났어요"), "끝났어요")
    }

    /// A package written for a later version should still work in this one:
    /// a name this build does not know is dropped rather than refusing the
    /// whole avatar.
    func test_aNameThisBuildDoesNotKnowIsIgnored() {
        let lines = AvatarLines.from(manifest: ["muted": "조용", "somethingLater": "?"])

        XCTAssertEqual(lines.text(.muted), "조용")
    }

    /// Only the pet's own speech is replaceable. A package that could rewrite
    /// what the app says as itself could lie about what the app is doing.
    func test_onlyThePetsOwnSpeechIsOnTheList() {
        let names = Set(AvatarLine.allCases.map(\.rawValue))

        XCTAssertEqual(names, [
            "muted", "permissionNeeded", "voicePermissionNeeded",
            "clientOffline", "runFinished", "approvalNeeded",
        ])
    }

    /// Every line has somewhere to fall back to, or a package that carries
    /// none would leave the pet with an empty bubble.
    func test_everyLineHasAFallback() {
        for line in AvatarLine.allCases {
            XCTAssertFalse(line.fallback.isEmpty, line.rawValue)
        }
    }
}
