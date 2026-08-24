//
//  WindowBackdrop.swift
//  Puck
//
//  The blurred desktop behind the client window.
//
//  A full-bleed NSVisualEffectView rather than a translucent window colour.
//  Making the *window* non-opaque on its own was tried before and left a
//  visibly translucent patch around the traffic lights (see
//  `NSWindow.applyGlassChrome`): a titled window keeps a real titlebar
//  container above the content, and with nothing behind it that layer blends
//  against the desktop instead of against the app. `fullSizeContentView`
//  means the content already runs up under it, so a backdrop that fills the
//  content fills the titlebar area too and the whole window blurs as one.
//

import AppKit
import SwiftUI

struct WindowBackdrop: NSViewRepresentable {
    /// `.underWindowBackground` is the material AppKit uses for exactly this
    /// -- a window's own ground -- and unlike `.sidebar` it does not lighten
    /// toward the top, which would put the band back that this is removing.
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        // Behind the window, so it blurs the desktop rather than the app's
        // own views; `.active` keeps it blurring when the window is not key,
        // which is when the pet is out on the desktop and the window is the
        // thing being looked past.
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
