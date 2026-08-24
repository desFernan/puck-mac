//
//  PetSizeSlider.swift
//  Puck
//
//  How big the pet is, as a bar standing up the island's left edge.
//
//  It has been three things. A drag handle at the island's top-right corner,
//  which was a guess until you were already dragging it; a horizontal slider
//  there, which could not be clicked at all, because the window's toolbar
//  covers that band whether or not anything is drawn in it; and the same
//  slider moved up into the toolbar, which worked but sat among buttons that
//  have nothing to do with the pet.
//
//  Upright at the island's left edge it is clear of the toolbar, it is on the
//  island it changes, and it points the way the pet grows.
//
//  The pet's size is in Settings too. Settings is a window you open, look
//  away from the pet to use, and close; this is the same number with the pet
//  in view while it changes. Only the size on the island -- on the desktop
//  the slider in Settings still decides.
//

import SwiftUI

struct PetSizeSlider: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    /// How tall the bar stands. Given by the island rather than fixed: the
    /// island is resizable, and a bar that kept one length would be a stub on
    /// a tall shelf and would overhang a short one.
    let length: CGFloat
    /// Sends the height to pet-app, which is the process that actually
    /// resizes the pet.
    let onChange: (CGFloat) -> Void

    @AppStorage(PetTankView.petHeightStorageKey) private var storedHeight = PetTankView.defaultPetHeight
    /// The island's own height, read for its ceiling rather than to draw it:
    /// pet-app refuses a shelf shorter than the pet standing on it, which
    /// reads as the pet declining to come home. So the slider stops where the
    /// island does, and making the pet bigger means making the island taller
    /// first.
    @AppStorage(PetTankView.heightStorageKey) private var storedIslandHeight = Double(PetTankView.islandHeight)

    /// How much room the bar takes across the island.
    static let thickness: CGFloat = 20

    /// Left at each end of the island, so the bar does not run into the
    /// corners it is drawn between.
    static let inset: CGFloat = 14

    /// How much of the island's width the bar takes, including the gap
    /// between it and the edge. The pet is kept out of this strip -- it is
    /// drawn by a window above this one, so a pet standing on the bar takes
    /// the drags meant for it.
    static let footprint: CGFloat = thickness + 12

    /// The tallest the pet may be right now: its own limit, or what the
    /// island can hold, whichever is lower.
    private var ceiling: Double {
        // A slider with an empty or inverted range traps, and the island's
        // height comes from UserDefaults, so the floor is enforced first.
        let island = storedIslandHeight.isFinite ? storedIslandHeight : Double(PetTankView.islandHeight)
        return max(
            PetTankView.minimumPetHeight + 1,
            min(PetTankView.maximumPetHeight, island - PetTankView.petHeadroom)
        )
    }

    /// The stored height, as a number the slider can actually take.
    private var safeHeight: Double {
        guard storedHeight.isFinite else { return PetTankView.defaultPetHeight }
        return min(max(storedHeight, PetTankView.minimumPetHeight), ceiling)
    }

    var body: some View {
        // Upright, because up is the way the pet grows. AppKit's own
        // vertical slider rather than a rotated SwiftUI one -- see
        // VerticalSlider for what that cost.
        VerticalSlider(
            value: Binding(get: { safeHeight }, set: { send($0) }),
            range: PetTankView.minimumPetHeight...ceiling
        )
        .frame(width: Self.thickness, height: length)
        // pet-app forgets the size when it quits, so the first window of the
        // next launch is where it finds out again.
        .onAppear { send(min(storedHeight, ceiling)) }
        // The island can be dragged shorter than the pet standing on it. The
        // pet gives way, since the alternative is a shelf it is refused from.
        .onChange(of: ceiling) { send(min(storedHeight, ceiling)) }
        .accessibilityLabel(Strings.text(.islandPetSize))
        .help(Strings.text(.islandPetSize))
    }

    private func send(_ height: Double) {
        storedHeight = height
        onChange(CGFloat(height))
    }
}
