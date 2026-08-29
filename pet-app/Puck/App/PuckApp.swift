//
//  PuckApp.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  @main entry point; bootstraps the LSUIElement menu-bar-resident lifecycle.
//
//  NOTE: the rest of the init order (permission self-check -> Overlay ->
//  BridgeServer -> GlobalHotkeyManager) is wired into AppDelegate as each
//  module gets implemented.

import AppKit

@main
enum PuckApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        // `NSApplication.delegate` is a weak reference, and a local is not a
        // lifetime ARC has to respect past its last use -- so in a release
        // build the delegate could be deallocated seconds after launch. What
        // that looked like was not a crash: AppKit owns the overlay window, so
        // the pet stayed on screen and simply stopped, because every timer
        // that drives it -- the frame clock above all -- captures `self`
        // weakly and goes quiet rather than complaining. The pet could not
        // walk, could not be dragged, and nothing in the log said why.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
