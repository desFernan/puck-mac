//
//  AppDelegate+MenuBar.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Status item wiring: the popover settings panel and the hide/show toggle.
//

import AppKit
import SwiftUI

extension AppDelegate {
    // MARK: - Menu bar

    func setUpMenuBar() {
        let menuBar = MenuBarController()
        menuBar.makePopoverContent = { [weak self] in self?.makeSettingsPanel() }
        menuBar.onOpenClient = { [weak self] in self?.openClientApp() }
        menuBarController = menuBar
    }

    /// The panel the status item drops. Rebuilt per open so it reflects live
    /// state -- which toys are out, whether the pet is hidden, whether
    /// Accessibility has been granted since last time.
    private func makeSettingsPanel() -> NSViewController {
        let view = SettingsView(
            store: settingsStore,
            onAvatarScaleChanged: { [weak self] scale in self?.applyLiveAvatarScale(scale) },
            initialToysOut: toyBox?.outToyNames ?? [],
            onToggleToy: { [weak self] toy in self?.toggleToy(toy) ?? [] },
            initialIsCharacterHidden: isCharacterHidden,
            onOpenClient: { [weak self] in
                // Closed first: the client app comes forward, and leaving the
                // panel floating over it reads as a stuck window.
                self?.menuBarController?.closePopover()
                self?.openClientApp()
            },
            onToggleVisibility: { [weak self] in self?.toggleCharacterVisibility() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        return NSHostingController(rootView: view)
    }

    /// Hides/shows the pet without quitting the
    /// app. orderOut/orderFrontRegardless rather than alphaValue -- an
    /// ordered-out window also stops receiving/dispatching mouse events, so
    /// there's nothing left to click on a hidden pet either.
    private func toggleCharacterVisibility() {
        isCharacterHidden.toggle()
        if let window = overlayController?.window {
            if isCharacterHidden {
                window.orderOut(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
    }
}
