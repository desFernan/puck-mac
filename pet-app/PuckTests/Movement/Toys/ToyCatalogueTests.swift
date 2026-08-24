//
//  ToyCatalogueTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The toy list and its artwork, one directory per toy under Resources/Toys,
//  keeping each toy's assets organized separately.
//

import XCTest
@testable import Puck

final class ToyCatalogueTests: XCTestCase {
    private var toysDirectory: URL {
        RepositorySources.url("Resources/Toys")
    }

    /// Each toy's artwork lives at Toys/<name>/<name>.png -- the lookup in
    /// BallController builds that path from the name alone, so a toy in the
    /// catalogue with no matching directory silently becomes a drawn circle.
    func test_everyToyHasItsArtworkInItsOwnDirectory() {
        for toy in ToyCatalogue.all {
            let artwork = toysDirectory
                .appendingPathComponent(toy.name, isDirectory: true)
                .appendingPathComponent("\(toy.name).png")

            XCTAssertTrue(
                FileManager.default.fileExists(atPath: artwork.path),
                "no artwork for \(toy.name) at Toys/\(toy.name)/\(toy.name).png"
            )
        }
    }

    func test_theCatalogueHasNoDuplicateNames() {
        XCTAssertEqual(Set(ToyCatalogue.all.map(\.name)).count, ToyCatalogue.all.count)
    }

    func test_theDefaultToyIsInTheCatalogue() {
        XCTAssertTrue(ToyCatalogue.all.contains(ToyCatalogue.default))
    }

    func test_everyToyHasARealSize() {
        for toy in ToyCatalogue.all {
            XCTAssertGreaterThan(toy.height, 0, "\(toy.name) has no height")
        }
    }

    func test_lookupFindsEachToyByName() {
        for toy in ToyCatalogue.all {
            XCTAssertEqual(ToyCatalogue.toy(named: toy.name), toy)
        }
    }

    /// A stored setting is just a string, and a toy that has been renamed or
    /// removed must not leave the user with no toy at all.
    func test_anUnknownNameFallsBackToTheDefault() {
        XCTAssertEqual(ToyCatalogue.toy(named: "no-such-toy"), ToyCatalogue.default)
        XCTAssertEqual(ToyCatalogue.toy(named: ""), ToyCatalogue.default)
    }

    /// The wand is much taller than it is wide; a square toy layer would
    /// letterbox it to a sliver, so its height has to account for that.
    func test_theWandIsSizedForATallShape() {
        XCTAssertGreaterThan(ToyCatalogue.wand.height, ToyCatalogue.pumpkin.height)
    }
}

extension ToyCatalogueTests {
    /// Decodable and shaped as the catalogue's height assumes. A corrupt or
    /// swapped file would otherwise only show up as a toy that renders as a
    /// plain circle, with nothing failing anywhere.
    func test_everyToyArtworkDecodesAndHasSensibleProportions() throws {
        for toy in ToyCatalogue.all {
            let artwork = toysDirectory
                .appendingPathComponent(toy.name, isDirectory: true)
                .appendingPathComponent("\(toy.name).png")
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(artwork as CFURL, nil), toy.name)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), toy.name)

            XCTAssertGreaterThan(image.width, 0, toy.name)
            XCTAssertGreaterThan(image.height, 0, toy.name)

            // The rendered width follows from the art, so a wildly extreme
            // aspect would come out unusably thin or wide at this height.
            let aspect = CGFloat(image.width) / CGFloat(image.height)
            let renderedWidth = toy.height * aspect
            XCTAssertGreaterThan(renderedWidth, 12, "\(toy.name) renders only \(renderedWidth)pt wide")
            XCTAssertLessThan(renderedWidth, 200, "\(toy.name) renders \(renderedWidth)pt wide")
        }
    }
}
