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

        // The notch offers the two things that are otherwise a trip
        // somewhere else: the toys, which are behind a right-click on this
        // same status item, and a line for the pet, which is behind a hotkey
        // most people never learn. Both act on the pet now, which is what
        // keeps this from being a second settings panel.
        notchPanelController.toysOut = { [weak self] in self?.toyBox?.outToyNames ?? [] }
        notchPanelController.onToggleToy = { [weak self] toy in self?.toggleToy(toy) ?? [] }
        // Through the quick-capture bubble's own entry point, so a turn
        // started at the notch and one started from the keyboard are the
        // same turn.
        notchPanelController.onSubmit = { [weak self] text in
            self?.submitFromInputBubble(text)
        }
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
            onOpenSettings: { [weak self] in
                // Closed first, for the reason the chat row closes it: the
                // window comes forward and a panel left floating over it
                // reads as stuck.
                self?.menuBarController?.closePopover()
                self?.showSettingsWindow()
            },
            onQuit: { NSApplication.shared.terminate(nil) },
            showsOnlyLiveControls: true
        )
        return NSHostingController(rootView: view)
    }

    /// The settings the panel no longer carries: sound, movement, and the
    /// app's own general settings.
    ///
    /// A window rather than more panel. The panel drops from the status item
    /// over whatever the user was doing, so it should hold what the pet is
    /// doing now -- which toys are out, how big, which avatar. Volume curves,
    /// walk speed and the language are set once and left, and having them
    /// there made a drop-down into a scrolling form.
    ///
    /// Kept between opens rather than rebuilt: unlike the panel, none of what
    /// is in here is live state that goes stale while the window is shut.
    func showSettingsWindow() {
        let window = settingsWindow ?? {
            let created = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            created.isReleasedWhenClosed = false
            created.contentViewController = NSHostingController(
                rootView: SettingsView(
                    store: settingsStore,
                    onNotchPanelChanged: { [weak self] _ in
                        guard let self, let controller = self.characterController else { return }
                        self.applyScreenNotches(to: controller)
                    }
                )
            )
            created.center()
            settingsWindow = created
            return created
        }()
        // Set on every show: the window outlives its closing, and the title
        // is the one part of it AppKit owns rather than SwiftUI -- nothing
        // would relabel it on a language change otherwise.
        window.title = Strings.text(.menuSettings)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
