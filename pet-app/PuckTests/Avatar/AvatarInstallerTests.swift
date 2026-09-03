//
//  AvatarInstallerTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  AppDelegate loads the avatar from ~/Library/Application Support/Puck/
//  Avatars/dummy, but nothing ever put it there — only the user-driven import
//  in AvatarManagementView copies anything. On a fresh clone the app launched
//  with no avatar at all, which is exactly what "클론 즉시 실행 보장" rules
//  out. The bundled package is seeded on first run instead.
//

import XCTest
@testable import Puck

final class AvatarInstallerTests: XCTestCase {
    private var bundled: URL!
    private var destinationRoot: URL!

    override func setUpWithError() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        bundled = sandbox.appendingPathComponent("Bundle/Avatars/dummy", isDirectory: true)
        destinationRoot = sandbox.appendingPathComponent("Support/Avatars", isDirectory: true)

        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: bundled.appendingPathComponent("manifest.json"))
        try FileManager.default.createDirectory(
            at: bundled.appendingPathComponent("sounds", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundled.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }

    func test_seedsTheBundledPackageWhenNothingIsInstalled() throws {
        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .installed)
        let installedManifest = destinationRoot.appendingPathComponent("dummy/manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedManifest.path))
    }

    func test_preservesSubdirectories() throws {
        _ = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        var isDirectory: ObjCBool = false
        let sounds = destinationRoot.appendingPathComponent("dummy/sounds")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sounds.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "the package layout must survive the copy")
    }

    /// An avatar the user chose is theirs. They may have imported a real one
    /// or hand-edited the manifest, and re-seeding on every launch would
    /// silently throw that away.
    func test_doesNotOverwriteAnAvatarTheUserImported() throws {
        let userManifest = try writeExistingInstall(markedAs: "user")

        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .alreadyPresent)
        XCTAssertEqual(try Data(contentsOf: userManifest), Data("{\"user\":true}".utf8))
    }

    /// A copy this app seeded is replaced when the app now carries a
    /// different one. It did not used to be, and that turned out to matter:
    /// the bundled avatar was withdrawn and replaced, and every machine that
    /// had already run the app went on using the withdrawn one, because the
    /// installer saw a manifest.json and stopped.
    func test_replacesItsOwnStaleCopy() throws {
        let manifest = try writeExistingInstall(markedAs: "bundled:something-older")

        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .replaced)
        XCTAssertNotEqual(try Data(contentsOf: manifest), Data("{\"user\":true}".utf8))
    }

    /// A copy with no marker beside it predates all of this -- which is
    /// exactly the machines still carrying the withdrawn package.
    func test_replacesACopyFromBeforeMarkersExisted() throws {
        _ = try writeExistingInstall(markedAs: nil)

        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .replaced)
    }

    /// And one that is already what the app carries is left alone, or every
    /// launch would re-copy a package for nothing.
    func test_leavesItsOwnCurrentCopyAlone() throws {
        _ = try writeExistingInstall(markedAs: AvatarInstaller.seedMarker(for: bundled))

        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .alreadyPresent)
    }

    /// An install that is already there, with `origin` recorded beside it or
    /// not. Returns the manifest's URL so a caller can check whether it
    /// survived.
    @discardableResult
    private func writeExistingInstall(markedAs origin: String?) throws -> URL {
        let package = destinationRoot.appendingPathComponent("dummy", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let manifest = package.appendingPathComponent("manifest.json")
        try Data("{\"user\":true}".utf8).write(to: manifest)
        if let origin {
            try Data(origin.utf8).write(to: package.appendingPathComponent(AvatarInstaller.markerName))
        }
        return manifest
    }

    /// The bundle genuinely may not carry a package — usdz assets are Git LFS
    /// tracked and are not committed yet, so a build made without them must
    /// report that rather than appear to succeed.
    func test_reportsMissingBundledPackage() throws {
        let absent = bundled.deletingLastPathComponent().appendingPathComponent("nope", isDirectory: true)

        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: absent, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .noBundledPackage)
    }

    /// A prior copy that died partway through (e.g. disk full, app killed
    /// mid-copy) leaves the destination directory present but without a
    /// manifest.json -- fileExists-on-the-directory alone treated this as
    /// "already installed" forever, permanently leaving a broken, invisible
    /// pet with no way to self-repair.
    func test_repairsAPartialPreviousInstall() throws {
        let partial = destinationRoot.appendingPathComponent("dummy", isDirectory: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        // No manifest.json written -- simulates a copy that never finished.

        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        XCTAssertEqual(outcome, .installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.appendingPathComponent("manifest.json").path))
    }

    /// AvatarManagementView's user-driven "Import Avatar Package…" flow used
    /// to reimplement this copy-in logic by hand and skip the LFS-pointer
    /// check entirely (found via review) -- overwriteExisting: true lets it
    /// route through here instead, replacing an existing install (the user
    /// explicitly chose to import over it) while keeping every safety check.
    func test_overwriteExisting_replacesAnAlreadyInstalledPackage() throws {
        try FileManager.default.createDirectory(
            at: destinationRoot.appendingPathComponent("dummy", isDirectory: true),
            withIntermediateDirectories: true
        )
        let staleManifest = destinationRoot.appendingPathComponent("dummy/manifest.json")
        try Data("{\"old\":true}".utf8).write(to: staleManifest)

        let outcome = AvatarInstaller.installIfNeeded(
            bundledPackage: bundled,
            intoAvatarsDirectory: destinationRoot,
            overwriteExisting: true
        )

        XCTAssertEqual(outcome, .installed)
        XCTAssertEqual(try Data(contentsOf: staleManifest), Data("{}".utf8))
    }

    /// The same un-pulled-LFS-pointer safety check must apply to a
    /// user-driven overwrite import, not just the first-run bootstrap seed.
    func test_overwriteExisting_stillDetectsUnpulledLFSPointerFiles() throws {
        let pointerText = "version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 12345\n"
        try Data(pointerText.utf8).write(to: bundled.appendingPathComponent("idle.usdz"))
        try FileManager.default.createDirectory(
            at: destinationRoot.appendingPathComponent("dummy", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{\"old\":true}".utf8).write(to: destinationRoot.appendingPathComponent("dummy/manifest.json"))

        let outcome = AvatarInstaller.installIfNeeded(
            bundledPackage: bundled,
            intoAvatarsDirectory: destinationRoot,
            overwriteExisting: true
        )

        guard case .failed = outcome else {
            return XCTFail("expected .failed for un-pulled LFS pointers, got \(outcome)")
        }
        XCTAssertEqual(
            try Data(contentsOf: destinationRoot.appendingPathComponent("dummy/manifest.json")),
            Data("{\"old\":true}".utf8),
            "must not clobber the existing install with a package containing unpulled LFS pointers"
        )
    }

    /// A contributor who cloned without `git lfs pull` gets ~130-byte LFS
    /// pointer text files named e.g. idle.usdz instead of the real usdz
    /// binary. Every layer above (AvatarLoader, USDZAvatar) would otherwise
    /// silently accept this and load a permanently invisible pet with no
    /// diagnostic pointing at the real cause.
    func test_detectsUnpulledLFSPointerFiles_andReportsFailedRatherThanInstalling() throws {
        let pointerText = "version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 12345\n"
        try Data(pointerText.utf8).write(to: bundled.appendingPathComponent("idle.usdz"))

        let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: destinationRoot)

        guard case .failed = outcome else {
            return XCTFail("expected .failed for un-pulled LFS pointers, got \(outcome)")
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destinationRoot.appendingPathComponent("dummy").path),
            "must not install a package containing unpulled LFS pointers"
        )
    }
}
