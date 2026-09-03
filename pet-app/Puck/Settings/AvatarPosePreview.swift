//
//  AvatarPosePreview.swift
//  Puck
//
//  The pet as it will look walking, climbing and hanging, with a way to turn
//  each of those the right way up.
//
//  It exists because the only way to find out an avatar climbs head-first was
//  to watch it climb, and the only way to fix it was to edit the artwork
//  outside the app and import it again. Four pictures and three buttons
//  answer both.
//
//  The preview composes the same pieces the renderer does, in the same order
//  -- the pose's own orientation, then the correction. What it cannot show is
//  the motion: the bounce is a function of time, and a still frame of a
//  waddle is a picture of a pet leaning over. Orientation is what this is
//  for, and orientation is what the bounce leaves alone.
//

import SwiftUI

struct AvatarPosePreviewSection: View {
    @ObservedObject private var localization = Localization.shared
    let avatarName: String
    let isMirrored: Bool
    @Binding var adjustments: AvatarPoseAdjustments

    var body: some View {
        SettingsSection(title: text(.posePreviewHeader)) {
            Text(text(.posePreviewExplanation))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
            ForEach(AvatarPose.allCases, id: \.self) { pose in
                row(for: pose)
            }
        }
    }

    private func row(for pose: AvatarPose) -> some View {
        HStack(spacing: ClientTheme.Metrics.spacingMedium) {
            AvatarPoseThumbnail(
                avatarName: avatarName,
                pose: pose,
                adjustment: adjustments[pose],
                isMirrored: isMirrored
            )
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(name(of: pose))
                Text(pose.clip)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Three buttons rather than a menu: each is one press with a
            // picture beside it that changes, which is the whole interaction.
            button("arrow.left.and.right.righttriangle.left.righttriangle.right") {
                adjustments[pose].flipsHorizontally.toggle()
            }
            button("arrow.up.and.down.righttriangle.up.righttriangle.down") {
                adjustments[pose].flipsVertically.toggle()
            }
            button("rotate.right") { adjustments[pose].rotate() }
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
        .padding(.vertical, ClientTheme.Metrics.spacingSmall)
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }

    private func name(of pose: AvatarPose) -> String {
        switch pose {
        case .walkingRight: return text(.poseWalkingRight)
        case .walkingLeft: return text(.poseWalkingLeft)
        case .climbingRightWall: return text(.poseClimbingRightWall)
        case .climbingLeftWall: return text(.poseClimbingLeftWall)
        case .onTheCeilingFacingRight: return text(.poseOnTheCeilingFacingRight)
        case .onTheCeilingFacingLeft: return text(.poseOnTheCeilingFacingLeft)
        }
    }

    private func text(_ key: L10nKey) -> String {
        Strings.text(key, language: localization.language)
    }
}

/// One pose, drawn the way the pet will draw it.
struct AvatarPoseThumbnail: View {
    let avatarName: String
    let pose: AvatarPose
    let adjustment: AvatarPoseAdjustment
    /// The global mirror, which the pet is drawn with and the preview was not.
    var isMirrored = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let image = sprite {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    // Composed in the one place the renderer composes it, so
                    // the picture here is the pet on the screen.
                    .scaleEffect(x: orientation.scaleX, y: orientation.scaleY)
                    .rotationEffect(.radians(Double(orientation.rotation)))
            } else {
                Image(systemName: "questionmark")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var orientation: AvatarPoseOrientation {
        AvatarPoseOrientation.of(pose, adjustment: adjustment, isMirrored: isMirrored)
    }

    private var sprite: NSImage? {
        let directory = AvatarManifestEditor.currentAvatarDirectory(named: avatarName)
        guard let manifest = try? AvatarManifestEditor.loadManifest(directory: directory),
              let fileName = Self.spriteName(for: pose.clip, in: manifest),
              let url = AvatarPackagePath.fileURL(in: directory, relativePath: "\(fileName).png")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    /// The file behind a clip, falling back to idle the way the renderer
    /// does.
    ///
    /// A clip is a `ClipReference`, not a string -- it can name a file or a
    /// span of an animation. Interpolating one straight into a path compiles,
    /// because interpolation accepts anything, and produces a name no file
    /// has: every preview came back empty and nothing said why.
    static func spriteName(for clip: String, in manifest: AvatarManifest) -> String? {
        if case .name(let name) = manifest.clips[clip] { return name }
        if case .name(let name) = manifest.clips["idle"] { return name }
        return nil
    }
}
