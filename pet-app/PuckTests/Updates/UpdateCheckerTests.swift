//
//  UpdateCheckerTests.swift
//  PuckTests
//
//  The checker's behaviour around the request: when it asks, when it does
//  not, and how often it can say the same thing.
//

import XCTest
@testable import Puck

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var preferences: UpdatePreferences!
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var requests = 0

    private let payload = Data("""
    [{"tag_name":"v0.3.0","name":"Puck 0.3.0","draft":false,"prerelease":false,
      "html_url":"https://github.com/desFernan/puck-mac/releases/tag/v0.3.0"}]
    """.utf8)

    override func setUpWithError() throws {
        suiteName = "puck.updates.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        preferences = UpdatePreferences(defaults: defaults)
        requests = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func checker(answering answer: Data? = nil) -> UpdateChecker {
        UpdateChecker(
            preferences: preferences,
            currentVersion: AppVersion("0.2.1"),
            now: { self.now },
            data: { [weak self] _ in
                self?.requests += 1
                guard let answer = answer ?? self?.payload else { throw URLError(.badServerResponse) }
                return answer
            }
        )
    }

    func test_aNewerVersionIsFoundAndAnnouncedOnce() async {
        let checker = self.checker()
        var announced: [String] = []
        checker.onFound = { announced.append($0.version.description) }

        await checker.check()
        await checker.check()

        XCTAssertEqual(checker.available?.version, AppVersion("0.3.0"))
        XCTAssertEqual(announced, ["0.3.0"], "the pet says it once, and Settings keeps it")
    }

    func test_switchedOffItDoesNotAsk() async {
        preferences.checksForUpdates = false

        await checker().checkIfDue()

        XCTAssertEqual(requests, 0, "the one request the user did not ask for is the one they can decline")
    }

    func test_itAsksOnceADayAndNotOncePerTick() async {
        let checker = self.checker()

        await checker.checkIfDue()
        await checker.checkIfDue()
        now = now.addingTimeInterval(UpdateCheck.interval)
        await checker.checkIfDue()

        XCTAssertEqual(requests, 2)
    }

    /// Written down before the request, not after: a GitHub that is down, or
    /// a machine with no network, must not turn into a check on every tick
    /// for as long as it stays that way.
    func test_aFailedCheckStillCountsAsHavingLooked() async {
        let checker = UpdateChecker(
            preferences: preferences,
            currentVersion: AppVersion("0.2.1"),
            now: { self.now },
            data: { [weak self] _ in
                self?.requests += 1
                throw URLError(.notConnectedToInternet)
            }
        )

        await checker.checkIfDue()
        await checker.checkIfDue()

        XCTAssertEqual(requests, 1)
        XCTAssertNil(checker.available)
    }

    func test_skippingAVersionPutsItAwayAndKeepsItAway() async throws {
        let checker = self.checker()
        await checker.check()

        checker.skip(try XCTUnwrap(checker.available))
        now = now.addingTimeInterval(UpdateCheck.interval)
        await checker.checkIfDue()

        XCTAssertNil(checker.available)
        XCTAssertEqual(preferences.skippedVersion, "0.3.0")
    }

    /// Pressing "check now" is asking, and the answer to a question somebody
    /// asked is not "I decided not to tell you".
    func test_checkingByHandIgnoresASkippedVersion() async {
        preferences.skippedVersion = "0.3.0"
        let checker = self.checker()

        await checker.check(honouringSkip: false)

        XCTAssertEqual(checker.available?.version, AppVersion("0.3.0"))
    }

    func test_nothingIsOfferedWhenThisBuildIsTheNewest() async {
        let checker = UpdateChecker(
            preferences: preferences,
            currentVersion: AppVersion("0.3.0"),
            now: { self.now },
            data: { _ in self.payload }
        )

        await checker.check()

        XCTAssertNil(checker.available)
    }
}
