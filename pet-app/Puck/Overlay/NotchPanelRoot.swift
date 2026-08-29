//
//  NotchPanelRoot.swift
//  Puck
//
//  The one view that watches what is playing.
//
//  It exists so the shut notch can change on its own. The controller rebuilds
//  the hosted view when the panel opens and shuts, which is fine for
//  something only the pointer changes -- but the wings appear when a song
//  starts, and nobody is pointing at anything when that happens. Reading the
//  store here means SwiftUI redraws them; leaving the controller to pass
//  values in meant it had to notice first.
//

import SwiftUI

struct NotchPanelRoot: View {
    @ObservedObject var music: NowPlayingStore

    let isOpen: Bool
    /// The hardware notch. What is drawn around it is worked out here,
    /// because whether the wings are out depends on the store.
    let notch: CGSize

    let toysOut: Set<String>
    let onToggleToy: (Toy) -> Set<String>
    let onSubmit: (String) -> Void

    private var isLive: Bool { music.track != nil }

    private var shutSize: CGSize {
        NotchPanelGeometry.shutRect(
            notch: CGRect(origin: .zero, size: notch),
            isLive: isLive
        ).size
    }

    var body: some View {
        NotchShell(
            isOpen: isOpen,
            notchSize: shutSize,
            shut: isLive
                ? AnyView(NotchWings(
                    artwork: music.artwork,
                    isPlaying: music.track?.isPlaying ?? false,
                    notchSize: notch
                ))
                : nil
        ) {
            NotchPanelView(
                music: music,
                // Passed in as well as gating the shell: the content is built
                // in both states so the field keeps what was typed across an
                // open and shut, which means `onAppear` fires once, while
                // shut, and never again. The view needs to be told.
                isOpen: isOpen,
                toysOut: toysOut,
                onToggleToy: onToggleToy,
                onSubmit: onSubmit
            )
        }
    }
}
