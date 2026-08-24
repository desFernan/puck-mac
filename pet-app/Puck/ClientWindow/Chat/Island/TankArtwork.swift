//
//  TankArtwork.swift
//  Puck
//
//  The picture the pet's island is filled with.
//
//  This was a set of moods to choose between, picked from a menu on the
//  strip: seven gradients behind the island, none of them on it. There is one
//  picture now and no menu -- what the island is made of is part of what the
//  app looks like, not a preference, and a picker offering six gradients
//  beside it was six ways to make it worse.
//
//  Replaces TankBackground; the setting it was stored under is left behind
//  rather than migrated, since nothing reads it any more.
//

import AppKit

enum TankArtwork {
    /// The file, both in the bundle's TankBackgrounds folder and in the
    /// customisation folder that overrides it.
    static let name = "seabed"

    /// Loaded once and kept: this is asked for on every frame the island
    /// draws, and decoding a wide PNG per frame is not a thing to do. A
    /// picture dropped in while the app is running is picked up at its next
    /// launch, which is what the README says.
    static func image() -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = resolvedURL(), let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// The customisation folder's copy if there is one, otherwise the app's
    /// own. Yours wins: that is the whole point of the folder.
    static func resolvedURL(
        custom: URL = Customisation.tank.appendingPathComponent("\(TankArtwork.name).png"),
        bundled: URL? = Bundle.main.url(forResource: TankArtwork.name, withExtension: "png", subdirectory: "TankBackgrounds")
    ) -> URL? {
        FileManager.default.fileExists(atPath: custom.path) ? custom : bundled
    }

    /// How wide one copy is per point of height. Guarded against a
    /// zero-height image, which would make the island's layout divide by it.
    static func aspect(_ image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }

    /// `nonisolated(unsafe)` because NSCache is documented as thread-safe --
    /// the compiler cannot see that, and the island draws from whichever
    /// context SwiftUI evaluates it in.
    private nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()
}
