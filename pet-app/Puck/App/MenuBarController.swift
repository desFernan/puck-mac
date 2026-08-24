//
//  MenuBarController.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  The status item, and the panel it drops down.
//
//  This used to be an NSMenu whose "설정…" item opened a separate
//  settings window. Now the icon drops the settings panel itself, the way
//  the pokoPet reference does -- one click, no menu in between.
//
//  Everything the menu used to carry lives in that panel instead: the toy
//  switches are its tile grid, and open-chat / hide / quit are the action
//  rows at its foot. So there are no NSMenuItem titles left to translate,
//  which is also why `applyLanguage` is gone -- the panel is SwiftUI and
//  recomputes its own text.
//

import AppKit

/// Which action a click on the status item icon performs. Split so the
/// common case (open the chat) is one
/// click, while the pet's own controls (toys, hide, quit) sit one click
/// further behind a right-click, where they don't get hit by accident.
enum MenuBarClick: Equatable {
    case openClient
    case showPanel

    init(eventType: NSEvent.EventType?) {
        self = eventType == .rightMouseUp ? .showPanel : .openClient
    }
}

/// `@MainActor`: it owns the status item, its popover and the panel inside
/// them. Every entry point is a click on that item or a call from the app
/// delegate, both of which are the main thread.
@MainActor
final class MenuBarController {
    /// Built afresh on every open rather than cached: the panel shows live
    /// state (which toys are out, whether Accessibility has been granted
    /// since last time, the current language), none of which a retained view
    /// would pick up.
    var makePopoverContent: (() -> NSViewController?)?
    /// Left-click -- opens PuckClient directly, bypassing the panel.
    var onOpenClient: (() -> Void)?

    /// Kept in step with SettingsView's own frame -- the popover and the view
    /// inside it have to agree or the panel opens clipped.
    static let panelSize = NSSize(width: 360, height: 560)

    private let statusItem: NSStatusItem

    /// The app's own face in the menu bar, drawn at the height AppKit gives a
    /// status item. Not a template image: it is a picture, and a template is
    /// a stencil -- macOS would throw the drawing away and fill the
    /// silhouette, which for a square is a black square.
    ///
    /// Falls back to the symbol it used to be if the asset is missing, since
    /// a status item with no image is an invisible menu bar item.
    private static func menuBarIcon() -> NSImage? {
        guard let icon = NSImage(named: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: AppIdentity.displayName)
        }
        icon.size = NSSize(width: 18, height: 18)
        icon.accessibilityDescription = AppIdentity.displayName
        return icon
    }
    private let popover = NSPopover()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick)
        // Left click alone triggers the button's action by default -- this
        // is what makes routing right-click to the same handler possible.
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Closes when the user clicks away, like every other menu bar panel.
        popover.behavior = .transient
    }

    @objc private func handleClick() {
        switch MenuBarClick(eventType: NSApp.currentEvent?.type) {
        case .showPanel:
            togglePopover()
        case .openClient:
            onOpenClient?()
        }
    }

    /// Second (right) click on the icon dismisses, matching how a menu behaved.
    private func togglePopover() {
        guard let button = statusItem.button else { return }
        guard !popover.isShown else {
            popover.performClose(nil)
            return
        }
        guard let content = makePopoverContent?() ?? nil else { return }
        content.preferredContentSize = Self.panelSize
        popover.contentViewController = content
        // Both, and before showing: without an explicit contentSize the
        // popover sized itself from a partially-laid-out hosting view and
        // opened clipped, showing the panel's bottom half with its header
        // off the top of the screen.
        popover.contentSize = Self.panelSize
        // An LSUIElement app doesn't become active just because its status
        // item was clicked, and an inactive popover's text fields never take
        // keystrokes -- without this the custom emotion name field can't be
        // typed into at all. Ahead of show(), so the popover isn't laid out
        // once and then re-laid-out by the activation.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// For panel actions that lead somewhere else (opening the client app),
    /// where leaving the panel hanging over the result reads as a bug.
    func closePopover() {
        popover.performClose(nil)
    }
}
