//
//  NotchPanelView.swift
//  Puck
//
//  What the notch opens into.
//
//  Two bands. What is playing across the top, because that is what a notch
//  panel is for and it is the part you look at rather than aim at; the things
//  you came to press along the bottom -- the toys, and a line for the pet.
//
//  The split is the point. The music band is wide and quiet and never moves;
//  the action band is a row of targets at a fixed height. Mixing them, which
//  is what the first version did by stacking everything, meant the toys sat
//  in a different place depending on whether a song had a long title.
//
//  Deliberately not a second settings panel. Everything here acts on the pet
//  or the music right now; anything set once and left is in the settings
//  window.
//

import SwiftUI

struct NotchPanelView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var music: NowPlayingStore

    /// Which toys are out, so the tiles can show it. Passed in rather than
    /// read here: the toy box is the truth and it lives in the app delegate.
    /// Whether the panel is open. The shell draws this view in both states,
    /// so it is the only thing that tells the view an open has happened.
    let isOpen: Bool
    let toysOut: Set<String>
    /// Puts a toy out or takes it away, and answers with what is out now.
    let onToggleToy: (Toy) -> Set<String>
    /// Sends a line to the pet, the same way the quick-capture bubble does.
    let onSubmit: (String) -> Void

    @State private var out: Set<String> = []
    @State private var prompt = ""
    @State private var hoveredToy: String?
    @State private var hoveredControl: String?
    @FocusState private var isPromptFocused: Bool

    init(
        music: NowPlayingStore,
        isOpen: Bool,
        toysOut: Set<String>,
        onToggleToy: @escaping (Toy) -> Set<String>,
        onSubmit: @escaping (String) -> Void
    ) {
        self.music = music
        self.isOpen = isOpen
        self.toysOut = toysOut
        self.onToggleToy = onToggleToy
        self.onSubmit = onSubmit
        // A seed and only a seed. The controller swaps the hosting view's
        // root view rather than rebuilding the hierarchy, so SwiftUI keeps
        // the `@State` it already has and throws this away on every open
        // after the first -- which is why `out` is also synced below.
        _out = State(initialValue: toysOut)
    }

    var body: some View {
        VStack(spacing: NotchPanelGeometry.bandGap) {
            musicBand
            Rectangle()
                .fill(NotchStyle.border)
                .frame(height: 1)
            actionBand
        }
        .padding(.horizontal, 18)
        .padding(.top, NotchPanelGeometry.topInset)
        .padding(.bottom, NotchPanelGeometry.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The toys can change while the panel is shut -- the status item's
        // panel puts them out too, and so does the pet kicking one away. The
        // controller asks again on every open, but the answer landed in a
        // property while the tiles were reading surviving `@State`: a tile
        // could show un-selected for a toy that was out, and clicking it then
        // took the toy away while the tile lit up.
        .onChange(of: toysOut) { _, fresh in out = fresh }
        // Focus follows the open, not the appear. `onAppear` fires once, for
        // the shut panel, and the window cannot become key then anyway.
        .onChange(of: isOpen) { _, open in isPromptFocused = open }
    }

    // MARK: - What is playing

    private var musicBand: some View {
        HStack(spacing: 14) {
            cover
            if let track = music.track {
                trackDetails(track)
                // A browser is driven with media keys, which need
                // Accessibility. Without it the buttons would be three
                // controls that quietly do nothing, so they are left out.
                if track.source.reportsPosition || MediaKeys.isAvailable {
                    transport(track)
                }
            } else {
                nothingPlaying
            }
        }
        .frame(height: NotchPanelGeometry.musicBandHeight)
    }

    private var cover: some View {
        // One shape whatever is inside it, so the row does not reflow the
        // moment a cover finishes loading.
        let shape = RoundedRectangle(cornerRadius: NotchStyle.radiusMedium, style: .continuous)
        let side = NotchPanelGeometry.musicBandHeight
        return shape
            .fill(NotchStyle.surface)
            .frame(width: side, height: side)
            .overlay {
                if let artwork = music.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        // Sized before it is clipped, not after. Filling a
                        // square with a picture that is not square makes the
                        // image itself larger than the square, and a clip
                        // shape applied to the image follows the image --
                        // so a wide cover spilled out over the title beside
                        // it. The frame is what the clip has to match.
                        .frame(width: side, height: side)
                        .clipShape(shape)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(NotchStyle.subtleForeground)
                }
            }
            .overlay { shape.strokeBorder(NotchStyle.border, lineWidth: 1) }
            .animation(NotchStyle.stateChange, value: music.artwork)
    }

    private func trackDetails(_ track: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(NotchStyle.foreground)
                .lineLimit(1)
            // The lyric takes the artist's line when there is one: the second
            // line is the only spare one, and a word being sung is worth more
            // than a name already under the cover art.
            Text(music.currentLyric ?? track.artist)
                .font(.system(size: 11))
                .foregroundStyle(
                    music.currentLyric == nil ? NotchStyle.mutedForeground : NotchStyle.foreground.opacity(0.85)
                )
                .lineLimit(1)
                .animation(NotchStyle.stateChange, value: music.currentLyric)
            Spacer(minLength: 0)
            // A browser gives a name and nothing else, so there is no
            // playhead to draw. An empty bar under a playing track reads as
            // a track stuck at zero.
            if track.source.reportsPosition {
                progress(track)
            } else {
                sourceName(track)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progress(_ track: NowPlaying) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(NotchStyle.track)
                    Capsule()
                        .fill(NotchStyle.foreground.opacity(0.85))
                        .frame(width: max(2, geometry.size.width * track.progress))
                }
            }
            .frame(height: 3)
            HStack(spacing: 6) {
                Text(TrackTime.text(track.position))
                if track.source.isWorthNaming {
                    // The system route finds whatever is playing, so which
                    // app that is stops being obvious.
                    Text(track.source.applicationName)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(TrackTime.text(track.duration))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(NotchStyle.subtleForeground)
        }
        // Moves with the clock rather than in steps, so a bar read once a
        // second still looks like it is running.
        .animation(.linear(duration: NowPlayingStore.interval), value: track.position)
    }

    /// Where it is coming from, in place of the progress bar. Worth saying:
    /// a title lifted from a tab is easier to trust once you can see it came
    /// from the browser.
    private func sourceName(_ track: NowPlaying) -> some View {
        Text(track.source.applicationName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(NotchStyle.subtleForeground)
    }

    private func transport(_ track: NowPlaying) -> some View {
        HStack(spacing: 6) {
            transportButton("backward.fill", size: 12) { music.send(.previous) }
            transportButton(track.isPlaying ? "pause.fill" : "play.fill", size: 15) {
                music.send(.playPause)
            }
            transportButton("forward.fill", size: 12) { music.send(.next) }
        }
    }

    private func transportButton(
        _ symbol: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredControl == symbol
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                // Full white under the pointer: three flat glyphs in a row
                // give no sign which one is about to be pressed, and a
                // transport that does not answer the pointer reads as an
                // illustration of a transport.
                .foregroundStyle(isHovered ? NotchStyle.foreground : NotchStyle.foreground.opacity(0.75))
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: NotchStyle.radiusSmall, style: .continuous)
                        .fill(isHovered ? NotchStyle.surfaceHovered : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredControl = $0 ? symbol : nil }
        .animation(NotchStyle.hover, value: isHovered)
        .accessibilityLabel(symbol)
    }

    private var nothingPlaying: some View {
        // Still the same row, so the panel does not change shape when the
        // music stops.
        Text(Strings.text(.notchNothingPlaying))
            .font(.system(size: 12))
            .foregroundStyle(NotchStyle.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - What you came to press

    private var actionBand: some View {
        HStack(spacing: 12) {
            toys
            promptField
        }
        .frame(height: NotchPanelGeometry.actionBandHeight)
    }

    private var toys: some View {
        HStack(spacing: 6) {
            ForEach(ToyCatalogue.all, id: \.name) { toy in
                Button { out = onToggleToy(toy) } label: { tile(toy) }
                    .buttonStyle(.plain)
                    .onHover { hoveredToy = $0 ? toy.name : nil }
                    .help(toy.name)
                    .accessibilityLabel(toy.name)
                    .accessibilityAddTraits(out.contains(toy.name) ? [.isSelected] : [])
            }
        }
        .fixedSize()
    }

    private func tile(_ toy: Toy) -> some View {
        let isOut = out.contains(toy.name)
        let isHovered = hoveredToy == toy.name
        return Group {
            if let image = ToyThumbnail.image(for: toy) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                // A toy whose artwork is missing is still one that can be put
                // out; an empty tile is a button nobody can aim at.
                Image(systemName: "circle.dashed").resizable().scaledToFit()
                    .foregroundStyle(NotchStyle.mutedForeground)
            }
        }
        .frame(width: 20, height: 20)
        .padding(7)
        .background {
            RoundedRectangle(cornerRadius: NotchStyle.radiusSmall, style: .continuous)
                // Three states worth telling apart, and only three: out,
                // about to be touched, and neither.
                .fill(isOut ? NotchStyle.surfaceActive : (isHovered ? NotchStyle.surfaceHovered : NotchStyle.surface))
        }
        .overlay {
            RoundedRectangle(cornerRadius: NotchStyle.radiusSmall, style: .continuous)
                .strokeBorder(isOut ? NotchStyle.borderActive : NotchStyle.border, lineWidth: 1)
        }
        // A toy going out or coming back is the tile's own news, so it is
        // worth a beat rather than a jump.
        .animation(NotchStyle.stateChange, value: isOut)
        .animation(NotchStyle.hover, value: isHovered)
    }

    private var promptField: some View {
        HStack(spacing: 8) {
            TextField(Strings.text(.bubblePlaceholder), text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(NotchStyle.foreground)
                .focused($isPromptFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(canSend ? .black : NotchStyle.subtleForeground)
                    .frame(width: 20, height: 20)
                    .background {
                        Circle().fill(canSend ? NotchStyle.foreground : NotchStyle.surface)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(NotchStyle.hover, value: canSend)
            .accessibilityLabel(Strings.text(.bubblePlaceholder))
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(height: 30)
        .background { Capsule().fill(NotchStyle.surface) }
        .overlay { Capsule().strokeBorder(NotchStyle.border, lineWidth: 1) }
        // Focus is driven from `isOpen` in `body` rather than from here: this
        // field is built while the panel is still shut, so `onAppear` fired
        // against a window that could not yet become key and the focus went
        // nowhere. The pointer is already here by the time it opens, and a
        // field you have to click first is a field you may as well not have.
    }

    private var canSend: Bool { !trimmed.isEmpty }

    private var trimmed: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        let text = trimmed
        guard !text.isEmpty else { return }
        prompt = ""
        onSubmit(text)
    }
}
