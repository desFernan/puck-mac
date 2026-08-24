//
//  AppLanguageTests.swift
//  Puck
//

import Combine
import XCTest
@testable import Puck

final class AppLanguageTests: XCTestCase {
    func test_resolvesAKnownRawValue() {
        XCTAssertEqual(AppLanguage.resolved(fromDefaultsValue: "ko"), .korean)
        XCTAssertEqual(AppLanguage.resolved(fromDefaultsValue: "en"), .english)
    }

    /// Unset and unrecognized have to land on the same value, or a stale
    /// defaults entry reads differently from a missing one.
    func test_unsetAndUnrecognizedBothFallBackToTheSystemDefault() {
        XCTAssertEqual(AppLanguage.resolved(fromDefaultsValue: nil), AppLanguage.systemDefault)
        XCTAssertEqual(AppLanguage.resolved(fromDefaultsValue: "kl"), AppLanguage.systemDefault)
        XCTAssertEqual(AppLanguage.resolved(fromDefaultsValue: ""), AppLanguage.systemDefault)
    }

    /// The value has to survive the notification, since the receiver is told
    /// not to re-read UserDefaults for it.
    func test_theValueRoundTripsThroughTheCrossProcessUserInfo() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(AppLanguage.resolved(fromCrossProcessUserInfo: language.crossProcessUserInfo), language)
        }
    }

    /// nil, not a default: a receiver that cannot tell "no value here" from
    /// "the value is Korean" would apply Korean on any malformed broadcast.
    func test_aNotificationWithNoRecognizableValueResolvesToNil() {
        XCTAssertNil(AppLanguage.resolved(fromCrossProcessUserInfo: nil))
        XCTAssertNil(AppLanguage.resolved(fromCrossProcessUserInfo: [:]))
        XCTAssertNil(AppLanguage.resolved(fromCrossProcessUserInfo: ["language": 7]))
    }

    /// `Locale.preferredLanguages` reports region and script too, so an
    /// exact-match lookup would send every "ko-KR" machine to English.
    func test_theSystemDefaultIsOneThisAppSpeaks() {
        XCTAssertTrue(AppLanguage.allCases.contains(AppLanguage.systemDefault))
    }

    func test_eachLanguageNamesItselfInItsOwnLanguage() {
        XCTAssertEqual(AppLanguage.korean.displayName, "한국어")
        XCTAssertEqual(AppLanguage.english.displayName, "English")
    }
}

final class LocalizationTests: XCTestCase {
    func test_startsOnTheLanguageItWasBuiltWith() {
        XCTAssertEqual(Localization(language: .english).language, .english)
    }

    func test_applyChangesTheLanguage() {
        let localization = Localization(language: .korean)
        localization.apply(.english)
        XCTAssertEqual(localization.language, .english)
    }

    /// A broadcast that arrives twice must not redraw every window twice.
    func test_applyingTheSameLanguageDoesNotNotifyViews() {
        let localization = Localization(language: .korean)
        var notifications = 0
        let subscription = localization.objectWillChange.sink { _ in notifications += 1 }
        defer { subscription.cancel() }

        localization.apply(.korean)
        XCTAssertEqual(notifications, 0)

        localization.apply(.english)
        XCTAssertEqual(notifications, 1, "a real change still has to notify")
    }
}
