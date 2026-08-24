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
        application.run()
    }
}
