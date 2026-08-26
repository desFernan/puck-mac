//
//  FootOnSurfaceTests.swift
//  Puck
//
//  What "the pet is standing on this" means, to the pixel.
//
//  A floor is a line and a pet's feet are a number, and the two are never
//  exactly equal after a walk of fractional steps -- so every question about
//  whether the pet is on a surface is really a question about how close is
//  close enough. This is that one answer, and what reads it is the check that
//  decides whether a Space switch should put the pet down on the floor that
//  just moved.
//

import XCTest
import CoreGraphics
@testable import Puck

final class FootOnSurfaceTests: XCTestCase {
    func test_feetExactlyOnTheSurface_areOnIt() {
        XCTAssertTrue(WindowSupport.stands(CGPoint(x: 100, y: 900), on: 900))
    }

    /// A walk lands on fractions of a pixel, so a floor is a band rather than
    /// a line -- either side of it.
    func test_feetWithinTheToleranceEitherWay_areStillOnIt() {
        XCTAssertTrue(WindowSupport.stands(CGPoint(x: 100, y: 900 - WindowSupport.footTolerance), on: 900))
        XCTAssertTrue(WindowSupport.stands(CGPoint(x: 100, y: 900 + WindowSupport.footTolerance), on: 900))
    }

    /// The case the Space switch turns on: a pet in mid-air was not standing
    /// on the floor that moved, and must be left where it meant to be.
    func test_feetWellAboveTheSurface_areNotOnIt() {
        XCTAssertFalse(WindowSupport.stands(CGPoint(x: 100, y: 700), on: 900))
    }

    func test_feetBelowTheSurface_areNotOnIt() {
        XCTAssertFalse(WindowSupport.stands(CGPoint(x: 100, y: 1000), on: 900))
    }
}
