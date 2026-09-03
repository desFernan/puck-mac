//
//  AvatarSpriteThumbnail.swift
//  Puck
//
//  One of an avatar's drawings, small.
//
//  The emotion list used to say "mapped" or "not mapped" beside each feeling,
//  which answers whether a picture is there but not which one -- and which
//  one is the entire question somebody mapping sixteen emotions is asking.
//  Sixteen words are also sixteen chances to have put the crying face on
//  "excited" and never find out.
//
//  Reads the file every time it is built. That is fine at this size and it is
//  what makes `refresh` work: the pictures change on disk, underneath SwiftUI,
//  which has no way to know a PNG was replaced.
//

import SwiftUI

struct AvatarSpriteThumbnail: View {
    let avatarName: String
    /// A clip name (`idle`, `walk`) or an emotion name. Exactly one.
    var clip: String?
    var emotion: String?
    /// Changed by whoever writes a new picture, to make this read the file
    /// again.
    var refresh: Int = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                } else {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
    }

    private var image: NSImage? {
        let directory = AvatarManifestEditor.currentAvatarDirectory(named: avatarName)
        guard let manifest = try? AvatarManifestEditor.loadManifest(directory: directory),
              let stem = stem(in: manifest),
              let url = AvatarPackagePath.fileURL(in: directory, relativePath: "\(stem).png")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    /// The file behind whichever of the two names was given.
    ///
    /// A clip or an emotion is a `ClipReference`, not a string: it can name a
    /// file or a span of an animation, and only the first has a picture to
    /// show. Interpolating one into a path compiles -- interpolation takes
    /// anything -- and yields a name no file has.
    private func stem(in manifest: AvatarManifest) -> String? {
        if let emotion, case .name(let name)? = manifest.emotions?[emotion] { return name }
        if let clip, case .name(let name)? = manifest.clips[clip] { return name }
        return nil
    }
}
