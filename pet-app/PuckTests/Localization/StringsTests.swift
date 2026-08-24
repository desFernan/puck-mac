//
//  StringsTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class StringsTests: XCTestCase {
    /// The one thing that would break the UI silently: a key with no
    /// string, falling back to the raw key name on screen. Asked of every
    /// language, since the fallback to Korean hides a missing translation
    /// from `text(_:language:)` itself.
    func test_everyKey_hasANonEmptyString_inEveryLanguage() {
        for language in AppLanguage.allCases {
            for key in L10nKey.allCases {
                let value = Strings.text(key, language: language)
                XCTAssertFalse(value.isEmpty, "\(key) is missing a string in \(language)")
                XCTAssertNotEqual(value, key.rawValue, "\(key) falls back to its raw key name in \(language)")
            }
        }
    }

    /// A key added to one table and forgotten in the other still renders --
    /// in the wrong language. Only this test can see that.
    func test_everyLanguageTranslatesEveryKey() {
        for language in AppLanguage.allCases {
            let missing = Set(L10nKey.allCases).subtracting(Strings.translatedKeys(in: language))
            XCTAssertTrue(missing.isEmpty, "\(language) is missing: \(missing.map(\.rawValue).sorted())")
        }
    }

    /// Named languages rather than the default, which follows whichever
    /// language the machine running the tests is set to.
    func test_text_returnsTheExpectedStringForAKnownKey() {
        XCTAssertEqual(Strings.text(.menuQuit, language: .korean), "Puck 종료")
        XCTAssertEqual(Strings.text(.menuQuit, language: .english), "Quit Puck")
    }

    /// Positional specifiers, because Korean and English disagree on the
    /// order these two numbers read in.
    func test_formatKeysKeepTheirArgumentsStraightInBothLanguages() {
        XCTAssertEqual(String(format: Strings.text(.mappedCountFormat, language: .korean), "2", "5"), "5개 중 2개 매핑됨")
        XCTAssertEqual(String(format: Strings.text(.mappedCountFormat, language: .english), "2", "5"), "2 of 5 mapped")
    }
}
