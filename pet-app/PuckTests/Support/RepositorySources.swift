//
//  RepositorySources.swift
//  PuckTests
//
//  Where the app's own source files are, for the handful of tests that check
//  a resource the build copies rather than the copy in the test bundle.
//
//  Each of those used to walk up from `#filePath` a fixed number of times.
//  That is a count of the directories between one test file and the repo
//  root, written down in the test -- so moving a test into a subdirectory
//  broke it, in a way that reads as the resource being missing rather than as
//  the test having moved. This searches instead.
//

import Foundation

enum RepositorySources {
    /// The directory holding `Puck/`, found by walking up from `file` until
    /// it appears. Falls back to the walked-out root, which fails the caller's
    /// own assertion with the path it looked in.
    static func root(from file: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: "\(file)")
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Puck/Resources").path) {
                return url
            }
        }
        return url
    }

    /// A path inside the app's own `Puck/` directory.
    static func url(_ relativePath: String, from file: StaticString = #filePath) -> URL {
        root(from: file).appendingPathComponent("Puck/\(relativePath)")
    }
}
