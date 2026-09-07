//
//  UpdateCheckTests.swift
//  PuckTests
//
//  Being told there is a newer Puck, and -- more often -- not being told.
//
//  The whole of this feature is arithmetic and restraint: which of two
//  version numbers is bigger, and how many of the answers are worth
//  interrupting somebody for. Both are testable without a network, which is
//  why the fetching is somewhere else.
//

import XCTest
@testable import Puck

final class AppVersionTests: XCTestCase {
    func test_versionsAreComparedByPartAndNotAsText() {
        // The one that matters: "0.10.0" sorts before "0.9.0" as text, so a
        // string comparison stops finding updates at the tenth minor release
        // and nobody notices for a year.
        XCTAssertTrue(AppVersion("0.10.0")! > AppVersion("0.9.0")!)
        XCTAssertTrue(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        XCTAssertTrue(AppVersion("0.2.2")! > AppVersion("0.2.1")!)
        XCTAssertEqual(AppVersion("0.2.1"), AppVersion("0.2.1"))
    }

    func test_aTagIsTheSameVersionAsTheNumberInIt() {
        XCTAssertEqual(AppVersion("v0.2.1"), AppVersion("0.2.1"))
    }

    /// A missing part is zero: "0.3" is a version somebody will tag one day.
    func test_aShortVersionFillsTheRestWithZero() {
        XCTAssertEqual(AppVersion("0.3"), AppVersion("0.3.0"))
        XCTAssertEqual(AppVersion("2"), AppVersion("2.0.0"))
    }

    /// Whether a pre-release is offered is the release's business, not the
    /// number's -- here it is simply the version it says it is.
    func test_aSuffixIsDroppedRatherThanRefused() {
        XCTAssertEqual(AppVersion("1.2.3-beta.1"), AppVersion("1.2.3"))
    }

    func test_somethingThatIsNotAVersionIsRefused() {
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
    }
}

final class ReleaseParsingTests: XCTestCase {
    private func payload(_ entries: [String]) -> Data {
        Data("[\(entries.joined(separator: ","))]".utf8)
    }

    private func release(tag: String, name: String = "", draft: Bool = false, prerelease: Bool = false) -> String {
        """
        {"tag_name":"\(tag)","name":"\(name)","draft":\(draft),"prerelease":\(prerelease),
         "html_url":"https://github.com/desFernan/puck-mac/releases/tag/\(tag)"}
        """
    }

    func test_theNewestIsTakenByVersionAndNotByPosition() {
        // GitHub's own order is by publication, which is not the same thing
        // the week somebody patches an older branch.
        let newest = Release.newest(in: payload([release(tag: "v0.1.9"), release(tag: "v0.3.0"), release(tag: "v0.2.5")]))

        XCTAssertEqual(newest?.version, AppVersion("0.3.0"))
    }

    func test_draftsAndPreReleasesAreNotOffered() {
        let newest = Release.newest(in: payload([
            release(tag: "v0.2.0"),
            release(tag: "v0.4.0", draft: true),
            release(tag: "v0.3.0", prerelease: true),
        ]))

        XCTAssertEqual(newest?.version, AppVersion("0.2.0"), "somebody on a stable build did not ask for a beta")
    }

    /// The `/latest` endpoint answers with one object rather than an array,
    /// and both shapes should read.
    func test_asingleReleaseObjectReadsToo() {
        XCTAssertEqual(Release.newest(in: Data(release(tag: "v1.0.0").utf8))?.version, AppVersion("1.0.0"))
    }

    func test_aReleaseWithoutAUsableTagIsSkipped() {
        XCTAssertNil(Release.newest(in: payload([release(tag: "nightly")])))
    }

    func test_nonsenseIsNilRatherThanACrash() {
        XCTAssertNil(Release.newest(in: Data("not json".utf8)))
        XCTAssertNil(Release.newest(in: Data()))
    }

    func test_aReleaseWithNoNameIsCalledByItsVersion() {
        XCTAssertEqual(Release.newest(in: Data(release(tag: "v1.2.3").utf8))?.name, "1.2.3")
    }
}

final class UpdateOfferTests: XCTestCase {
    private let payload = Data("""
    [{"tag_name":"v0.3.0","name":"Puck 0.3.0","draft":false,"prerelease":false,
      "html_url":"https://github.com/desFernan/puck-mac/releases/tag/v0.3.0"}]
    """.utf8)

    func test_aNewerReleaseIsOffered() {
        let offer = UpdateCheck.offer(payload: payload, current: AppVersion("0.2.1"))

        XCTAssertEqual(offer?.version, AppVersion("0.3.0"))
        XCTAssertEqual(offer?.url.absoluteString, "https://github.com/desFernan/puck-mac/releases/tag/v0.3.0")
    }

    /// The ordinary answer, and the one that has to stay silent.
    func test_theSameVersionIsNotAnUpdate() {
        XCTAssertNil(UpdateCheck.offer(payload: payload, current: AppVersion("0.3.0")))
    }

    func test_anOlderReleaseThanThisBuildIsNotAnUpdate() {
        // Somebody running a build from source is ahead of what is published,
        // and telling them to downgrade is worse than saying nothing.
        XCTAssertNil(UpdateCheck.offer(payload: payload, current: AppVersion("0.4.0")))
    }

    func test_aVersionAlreadyTurnedDownIsNotOfferedAgain() {
        XCTAssertNil(UpdateCheck.offer(payload: payload, current: AppVersion("0.2.1"), skipping: "0.3.0"))
    }

    /// Skipping one version is not skipping every version after it.
    func test_aNewerVersionThanTheSkippedOneIsStillOffered() {
        XCTAssertEqual(
            UpdateCheck.offer(payload: payload, current: AppVersion("0.2.1"), skipping: "0.2.9")?.version,
            AppVersion("0.3.0")
        )
    }

    /// A bundle with no version of its own -- which is a test host, not a
    /// shipped app -- has nothing to compare against.
    func test_withoutAVersionOfItsOwnNothingIsOffered() {
        XCTAssertNil(UpdateCheck.offer(payload: payload, current: nil))
    }
}

final class UpdateCheckScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// The first launch after an install is when somebody most wants to know
    /// they are already behind -- a link sat in a chat for a month.
    func test_neverCheckedIsDue() {
        XCTAssertTrue(UpdateCheck.isDue(lastCheckedAt: nil, now: now))
    }

    func test_notDueAgainWithinTheDay() {
        XCTAssertFalse(UpdateCheck.isDue(lastCheckedAt: now.addingTimeInterval(-3600), now: now))
    }

    func test_dueOnceTheDayHasTurned() {
        XCTAssertTrue(UpdateCheck.isDue(lastCheckedAt: now.addingTimeInterval(-UpdateCheck.interval), now: now))
    }

    /// A machine that woke in another timezone, or a date set by hand, would
    /// otherwise put the next check arbitrarily far into the future.
    func test_aClockThatWentBackwardsDoesNotPostponeTheCheckForever() {
        XCTAssertTrue(UpdateCheck.isDue(lastCheckedAt: now.addingTimeInterval(60 * 60 * 24 * 400), now: now))
    }
}
