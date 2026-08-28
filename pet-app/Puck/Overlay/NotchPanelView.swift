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
    let toysOut: Set<String>
    /// Puts a toy out or takes it away, and answers with what is out now.
    let onToggleToy: (Toy) -> Set<String>
    /// Sends a line to the pet, the same way the quick-capture bubble does.
    let onSubmit: (String) -> Void

    @State private var out: Set<String> = []
    @State private var prompt = ""
    @State private var hoveredToy: String?
    @FocusState private var isPromptFocused: Bool

    init(
        music: NowPlayingStore,
        toysOut: Set<String>,
        onToggleToy: @escaping (Toy) -> Set<String>,
        onSubmit: @escaping (String) -> Void
    ) {
        self.music = music
        self.toysOut = toysOut
        self.onToggleToy = onToggleToy
        self.onSubmit = onSubmit
        _out = State(initialValue: toysOut)
    }

    var body: some View {
        VStack(spacing: NotchPanelGeometry.bandGap) {
            musicBand
            Divider().overlay(.white.opacity(0.10))
            actionBand
        }
        .padding(.horizontal, 18)
        .padding(.top, NotchPanelGeometry.topInset)
        .padding(.bottom, NotchPanelGeometry.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.07))
            .frame(width: 62, height: 62)
            .overlay {
                if let artwork = music.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.18), value: music.artwork)
    }

    private func trackDetails(_ track: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            // The lyric takes the artist's line when there is one: the second
            // line is the only spare one, and a word being sung is worth more
            // than a name already under the cover art.
            Text(music.currentLyric ?? track.artist)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(music.currentLyric == nil ? 0.55 : 0.85))
                .lineLimit(1)
                .animation(.easeOut(duration: 0.2), value: music.currentLyric)
            Spacer(minLength: 0)
            // A browser gives a name and nothing else, so there is no
            // playhead to draw. An empty bar under a playing track reads as
            // a track stuck at zero.
            if track.source.reportsPosition {
                progress(track)
            } else {
                sourceLabel(track)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progress(_ track: NowPlaying) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: max(2, geometry.size.width * track.progress))
                }
            }
            .frame(height: 3)
            HStack {
                Text(TrackTime.text(track.position))
                Spacer(minLength: 0)
                Text(TrackTime.text(track.duration))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.40))
        }
        // Moves with the clock rather than in steps, so a bar read once a
        // second still looks like it is running.
        .animation(.linear(duration: NowPlayingStore.interval), value: track.position)
    }

    /// Where it is coming from, in place of the progress bar. Worth saying:
    /// a title lifted from a tab is easier to trust once you can see it came
    /// from the browser.
    private func sourceLabel(_ track: NowPlaying) -> some View {
        Text(track.source.applicationName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.40))
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
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
    }

    private var nothingPlaying: some View {
        // Still the same row, so the panel does not change shape when the
        // music stops.
        Text(Strings.text(.notchNothingPlaying))
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.40))
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
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 20, height: 20)
        .padding(7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                // Three states worth telling apart, and only three: out,
                // about to be touched, and neither.
                .fill(.white.opacity(isOut ? 0.20 : (isHovered ? 0.11 : 0.06)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(isOut ? 0.28 : 0.08), lineWidth: 1)
        }
        // A toy going out or coming back is the tile's own news, so it is
        // worth a beat rather than a jump.
        .animation(.easeOut(duration: 0.14), value: isOut)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var promptField: some View {
        HStack(spacing: 8) {
            TextField(Strings.text(.bubblePlaceholder), text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($isPromptFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(canSend ? .black : .white.opacity(0.35))
                    .frame(width: 20, height: 20)
                    .background {
                        Circle().fill(canSend ? .white : .white.opacity(0.10))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.easeOut(duration: 0.12), value: canSend)
            .accessibilityLabel(Strings.text(.bubblePlaceholder))
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(height: 30)
        .background { Capsule().fill(.white.opacity(0.08)) }
        .overlay { Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1) }
        // Focused when the panel appears: the pointer is already here, and a
        // field you have to click first is a field you may as well not have.
        .onAppear { isPromptFocused = true }
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
