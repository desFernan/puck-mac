//
//  NotchPanelView.swift
//  Puck
//
//  What the notch opens into.
//
//  Two things, both of which are otherwise a trip somewhere else: the toys,
//  which live behind a right-click on the status item, and a line of text for
//  the pet, which lives behind a hotkey most people never learn. The notch is
//  the one place on the screen that is always in the same spot and always
//  reachable with the pointer already moving upward, which is what makes it
//  worth putting them there.
//
//  Deliberately not a second settings panel. Everything here acts on the pet
//  right now; anything you set once and leave is in the settings window.
//

import SwiftUI

struct NotchPanelView: View {
    @ObservedObject private var localization = Localization.shared

    /// Which toys are out, so the tiles can show it. Passed in rather than
    /// read here: the toy box is the truth and it lives in the app delegate.
    let toysOut: Set<String>
    /// Puts a toy out or takes it away, and answers with what is out now.
    let onToggleToy: (Toy) -> Set<String>
    /// Sends a line to the pet's agent, the same way the quick-capture
    /// bubble does.
    let onSubmit: (String) -> Void

    @State private var out: Set<String> = []
    @State private var prompt = ""
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
        VStack(alignment: .leading, spacing: 12) {
            toys
            prompt(field: ())
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var toys: some View {
        HStack(spacing: 10) {
            ForEach(ToyCatalogue.all, id: \.name) { toy in
                Button {
                    out = onToggleToy(toy)
                } label: {
                    toyTile(toy)
                }
                .buttonStyle(.plain)
                .help(toy.name)
                .accessibilityLabel(toy.name)
                .accessibilityAddTraits(out.contains(toy.name) ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }

    private func toyTile(_ toy: Toy) -> some View {
        let isOut = out.contains(toy.name)
        return Group {
            if let image = ToyThumbnail.image(for: toy) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                // A toy whose artwork is missing is still a toy that can be
                // put out; a tile with nothing in it is a button nobody can
                // aim at.
                Image(systemName: "circle.dashed").resizable().scaledToFit()
            }
        }
        .frame(width: 26, height: 26)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                // Lit when the toy is out, which is the only state worth
                // showing: the tiles are a row of switches, not a menu.
                .fill(Color.white.opacity(isOut ? 0.22 : 0.08))
        )
    }

    /// The parameter is a placeholder so the name does not collide with the
    /// `prompt` state this reads.
    private func prompt(field: Void) -> some View {
        HStack(spacing: 8) {
            TextField(Strings.text(.bubblePlaceholder), text: $prompt)
                .textFieldStyle(.plain)
                .focused($isPromptFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty)
            .accessibilityLabel(Strings.text(.bubblePlaceholder))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
        // Focused when the panel appears: the pointer is already here, and a
        // field you have to click first is a field you may as well not have.
        .onAppear { isPromptFocused = true }
    }

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
