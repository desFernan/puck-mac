//
//  IslandFoldButton.swift
//  Puck
//
//  Folds the island down to a band, and back.
//
//  In the window's toolbar rather than on the island. It was on the island
//  first, at the far end, which put it where the thing it acts on is -- but
//  the island is also the one surface in this window a pet walks about on,
//  and a control drawn under a pet is a control the pet stands on. Beside the
//  editor and terminal toggles it is what it actually is: a view control for
//  a part of the window, next to the other two.
//
//  Owns no state of its own. The island's shape is read from the same stored
//  value on both sides, so the button and the island cannot disagree about
//  which shape it is in.
//

import SwiftUI

struct IslandFoldButton: View {
    /// Sends the pet's height on the island to pet-app, which is the process
    /// that actually resizes it.
    let onPetHeightChange: (CGFloat) -> Void

    @ObservedObject private var localization = Localization.shared

    @AppStorage(PetTankView.collapsedStorageKey) private var isCollapsed = false
    @AppStorage(PetTankView.petHeightStorageKey) private var storedPetHeight = PetTankView.defaultPetHeight
    @AppStorage(PetTankView.heightStorageKey) private var storedIslandHeight = Double(PetTankView.islandHeight)

    var body: some View {
        Button {
            isCollapsed.toggle()
            onPetHeightChange(CGFloat(petHeightForCurrentShape))
        } label: {
            Label(title, systemImage: isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
        }
        .help(title)
    }

    private var title: String {
        Strings.text(isCollapsed ? .islandUnfold : .islandFold)
    }

    /// The pet's height for the shape the island is in now.
    ///
    /// The size travels with the shape because it has to: pet-app refuses a
    /// tank shorter than the pet standing in it, and the refusal is silent
    /// from the outside -- the pet just stays on the desktop, and the button
    /// reads as broken.
    private var petHeightForCurrentShape: Double {
        guard !isCollapsed else { return PetTankView.collapsedPetHeight }
        // The same ceiling the size slider draws itself against, so unfolding
        // cannot ask for a pet the island it is opening to cannot hold.
        let island = storedIslandHeight.isFinite ? storedIslandHeight : Double(PetTankView.islandHeight)
        return min(storedPetHeight, island - PetTankView.petHeadroom)
    }
}
