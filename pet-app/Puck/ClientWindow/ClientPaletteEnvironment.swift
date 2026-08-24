//
//  ClientPaletteEnvironment.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Injects the active ClientPalette down the view tree so nested views
//  (message bubbles, sidebar rows, popovers) don't need it threaded through
//  every init -- ClientWindowView sets this once at the root from
//  ClientWindowStore.themeStyle.palette.
//

import SwiftUI

private struct ClientPaletteKey: EnvironmentKey {
    static let defaultValue = ClientPalette.dark
}

extension EnvironmentValues {
    var clientPalette: ClientPalette {
        get { self[ClientPaletteKey.self] }
        set { self[ClientPaletteKey.self] = newValue }
    }
}
