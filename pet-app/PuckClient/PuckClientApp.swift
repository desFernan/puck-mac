//
//  PuckClientApp.swift
//  PuckClient
//
//  owner: 박해영 (Haeyoung Park)
//  @main entry point -- a regular (Dock-resident) app, unlike Puck's
//  LSUIElement menu-bar lifecycle. This app *is* the Claude-Desktop-style
//  client window; Puck stays a pure pet + bridge.sock host (2026-07-30).
//

import AppKit

@main
enum PuckClientApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        // No nib, so nothing supplies a main menu -- and with no menu, every
        // standard shortcut (Cmd+Q/W/M, Cmd+C/V in the chat field) is dead.
        application.mainMenu = ClientMainMenu.make(appName: AppIdentity.clientDisplayName)
        application.run()
    }
}
