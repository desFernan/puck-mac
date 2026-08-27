//
//  ToyPresentation.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Toy -> display label/tint, shared by the Settings toy grid and the notch
//  toy buttons so the two surfaces can't drift apart on what a toy is
//  called or coloured.
//

import SwiftUI

enum ToyPresentation {
    static func label(for toy: Toy) -> L10nKey {
        toy.name == ToyCatalogue.wand.name ? .toyWand : .toyPumpkin
    }

    /// The wash behind each toy, taken from the artwork's own colour -- these
    /// read as "that orange pumpkin" rather than as app branding. A toy added
    /// to the catalogue without an entry here still gets a tile, just a grey
    /// one.
    static func tint(for toy: Toy) -> Color {
        switch toy.name {
        case ToyCatalogue.pumpkin.name: return .orange
        case ToyCatalogue.wand.name: return .purple
        default: return .gray
        }
    }
}
