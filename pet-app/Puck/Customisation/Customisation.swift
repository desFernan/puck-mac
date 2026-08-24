//
//  Customisation.swift
//  Puck
//
//  The one folder the things you can swap live in.
//
//  Avatars were already installed into Application Support and picked from
//  Settings, but nothing said where that was, and the tank's picture could
//  only be changed by rebuilding the app. Both are files somebody should be
//  able to drop in, so both live here:
//
//      ~/Library/Application Support/Puck/
//          Avatars/<name>/manifest.json, *.png, sounds/
//          Tank/seabed.png
//
//  See the README for what goes in an avatar package.
//

import AppKit

enum Customisation {
    /// `~/Library/Application Support/Puck`.
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
    }

    /// One folder per character. AvatarInstaller puts the bundled one here on
    /// first launch, and Settings lists whatever else is beside it.
    static var avatars: URL {
        directory.appendingPathComponent("Avatars", isDirectory: true)
    }

    /// The picture the island is filled with, if there is one here. The app
    /// ships its own; this is what overrides it.
    static var tank: URL {
        directory.appendingPathComponent("Tank", isDirectory: true)
    }

    /// Makes the folders, so opening them shows where things go rather than
    /// nothing at all -- the tank one does not otherwise exist until somebody
    /// creates it, which is the moment they need to know its name.
    static func createDirectories() {
        for url in [avatars, tank] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Opens the folder in Finder, having made sure it is there.
    static func reveal() {
        createDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([avatars, tank])
    }
}
