//
//  ClientThemeStyleTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class ClientThemeStyleTests: XCTestCase {
    func test_listsTheThemesInTheOrderThePickerShowsThem() {
        XCTAssertEqual(ClientThemeStyle.allCases, [.light, .dark, .vercelDark, .tokyoNight])
    }

    /// A theme is a set of choices about code as well as chrome. Deriving the
    /// syntax colours from the interface ones is what made every theme's code
    /// look the same, so each has to bring its own.
    func test_everyThemeBringsItsOwnSyntaxColours() {
        let keywords = Set(ClientThemeStyle.allCases.map { $0.palette.syntax.keyword.description })
        XCTAssertEqual(keywords.count, ClientThemeStyle.allCases.count, "two themes share a keyword colour")
        for style in ClientThemeStyle.allCases {
            let syntax = style.palette.syntax
            XCTAssertNotEqual(syntax.comment, style.palette.textPrimary, "\(style): comments must not be body text")
            XCTAssertNotEqual(syntax.string, syntax.keyword, "\(style): string and keyword must be tellable apart")
        }
    }

    func test_light_isLightColorScheme() {
        XCTAssertEqual(ClientThemeStyle.light.colorScheme, .light)
    }

    func test_everyDarkThemeReportsTheDarkColorScheme() {
        for style in ClientThemeStyle.allCases where style != .light {
            XCTAssertEqual(style.colorScheme, .dark, "\(style) is a dark theme")
        }
    }

    func test_displayName_isDistinctForEveryCase() {
        let names = Set(ClientThemeStyle.allCases.map(\.displayName))
        XCTAssertEqual(names.count, ClientThemeStyle.allCases.count)
    }

    func test_resolved_withKnownRawValue_returnsMatchingCase() {
        XCTAssertEqual(ClientThemeStyle.resolved(fromDefaultsValue: "light"), .light)
    }

    func test_resolved_withNilOrUnknownRawValue_defaultsToDark() {
        XCTAssertEqual(ClientThemeStyle.resolved(fromDefaultsValue: nil), .dark)
        XCTAssertEqual(ClientThemeStyle.resolved(fromDefaultsValue: "glass"), .dark)
    }

    func test_crossProcessUserInfo_roundTripsThroughResolved() {
        for style in ClientThemeStyle.allCases {
            XCTAssertEqual(ClientThemeStyle.resolved(fromCrossProcessUserInfo: style.crossProcessUserInfo), style)
        }
    }

    func test_resolved_fromMissingCrossProcessUserInfoKey_isNil() {
        XCTAssertNil(ClientThemeStyle.resolved(fromCrossProcessUserInfo: [:]))
        XCTAssertNil(ClientThemeStyle.resolved(fromCrossProcessUserInfo: nil))
    }
}
