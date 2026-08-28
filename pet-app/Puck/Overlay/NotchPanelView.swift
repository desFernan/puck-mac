//
//  NotchPanelView.swift
//  Puck
//
//  What the notch opens into.
//
//  Two things, both otherwise a trip somewhere else: the toys, which live
//  behind a right-click on the status item, and a line for the pet, which
//  lives behind a hotkey most people never learn. The notch is the one place
//  on screen that is always in the same spot and always reachable with the
//  pointer already moving upward, which is what makes it worth putting them
//  there.
//
//  Deliberately not a second settings panel. Everything here acts on the pet
//  right now; anything set once and left is in the settings window.
//
//  Laid out against the shape rather than in a box inside it: the padding is
//  wider at the bottom than the top because the bottom corners are rounded
//  and content run up against a curve looks closer to the edge than content
//  beside a straight one.
//

import SwiftUI

struct NotchPanelView: View {
    @ObservedObject private var localization = Localization.shared

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
        toysOut: Set<String>,
        onToggleToy: @escaping (Toy) -> Set<String>,
        onSubmit: @escaping (String) -> Void
    ) {
        self.toysOut = toysOut
        self.onToggleToy = onToggleToy
        self.onSubmit = onSubmit
        _out = State(initialValue: toysOut)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toys
            promptField
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Toys

    private var toys: some View {
        HStack(spacing: 10) {
            ForEach(ToyCatalogue.all, id: \.name) { toy in
                Button { out = onToggleToy(toy) } label: { tile(toy) }
                    .buttonStyle(.plain)
                    .onHover { hoveredToy = $0 ? toy.name : nil }
                    .help(toy.name)
                    .accessibilityLabel(toy.name)
                    .accessibilityAddTraits(out.contains(toy.name) ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
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
        .frame(width: 24, height: 24)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                // Three states worth telling apart, and only three: out,
                // about to be touched, and neither.
                .fill(.white.opacity(isOut ? 0.20 : (isHovered ? 0.11 : 0.06)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(isOut ? 0.28 : 0.08), lineWidth: 1)
        }
        // A toy going out or coming back is the tile's own news, so it is
        // worth a beat rather than a jump.
        .animation(.easeOut(duration: 0.14), value: isOut)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    // MARK: - Prompt

    private var promptField: some View {
        HStack(spacing: 10) {
            TextField(Strings.text(.bubblePlaceholder), text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($isPromptFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(canSend ? .black : .white.opacity(0.35))
                    .frame(width: 22, height: 22)
                    .background {
                        Circle().fill(canSend ? .white : .white.opacity(0.10))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.easeOut(duration: 0.12), value: canSend)
            .accessibilityLabel(Strings.text(.bubblePlaceholder))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(.white.opacity(0.08))
        }
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
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
