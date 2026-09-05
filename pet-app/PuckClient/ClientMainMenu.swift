//
//  ClientMainMenu.swift
//  PuckClient
//
//  owner: 박해영 (Haeyoung Park)
//  PuckClient's main menu, built in code.
//
//  The standard commands have to work here like anywhere else. An AppKit app
//  assembled by hand (no MainMenu.xib -- this project generates
//  its Xcode project and has no nibs) starts with *no* main menu at all, and
//  every standard shortcut is a menu item's key equivalent: with no menu,
//  Cmd+Q/W/M and even Cmd+C/V in the chat's text field are dead keys. This is
//  the smallest menu that makes them work again. PuckTests compiles this
//  one file directly (see project.yml) rather than reaching it through the
//  Puck target, which never uses it.
//
//  Titles are Korean, matching the rest of the app's UI text.
//

import AppKit

enum ClientMainMenu {
    static func make(appName: String = "PuckClient") -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu: appMenu(appName: appName))
        mainMenu.addItem(submenu: editMenu())
        mainMenu.addItem(submenu: windowMenu())
        return mainMenu
    }

    private static func appMenu(appName: String) -> NSMenu {
        // macOS titles the first menu with the app name itself, whatever this
        // menu's own title is.
        let menu = NSMenu(title: appName)
        menu.addItem(title: "\(appName) 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        menu.addItem(.separator())
        // Raw string selector, not #selector(AppDelegate.showSettings(_:)) --
        // PuckTests compiles this file directly without AppDelegate (see
        // this file's header), so a typed reference to it wouldn't build
        // there. Same reasoning as the undo/redo items below. Resolved via
        // the responder chain (nil target): AppKit checks NSApp.delegate as
        // a target-for-action fallback, which is where AppDelegate implements
        // this -- the agent's settings live in this app, not the pet's.
        //
        // NSSelectorFromString rather than Selector(("...")): the compiler can
        // see AppDelegate's method in this target and tells you to write
        // #selector instead, which is the one thing that cannot be written
        // here. The two build the same selector.
        menu.addItem(title: "설정…", action: NSSelectorFromString("showSettings:"), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(title: "\(appName) 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(
            title: "다른 항목 가리기",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option]
        )
        menu.addItem(title: "모두 보기", action: #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        // Quits this app only. The pet is a separate process (Puck) and
        // keeps running: quitting or minimising this window must never take
        // the pet down with it.
        menu.addItem(title: "\(appName) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// The chat input is an ordinary NSTextField underneath: without these
    /// items, copy/paste/select-all inside it do nothing.
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "편집")
        menu.addItem(title: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(title: "다시 실행", action: Selector(("redo:")), keyEquivalent: "z", modifiers: [.command, .shift])
        menu.addItem(.separator())
        menu.addItem(title: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(title: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(title: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(title: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "윈도우")
        menu.addItem(title: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(title: "확대/축소", action: #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        // Closing the window quits: applicationShouldTerminateAfterLast-
        // WindowClosed is true, so ⌘W ends the app and takes any turn still
        // running with it (applicationWillTerminate stops the ACP children).
        // Said out loud because the comment here used to claim the opposite,
        // and anyone wiring a second window off this menu would believe it.
        menu.addItem(title: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        addItem(item)
    }

    @discardableResult
    func addItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        addItem(item)
        return item
    }
}
