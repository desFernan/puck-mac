//
//  AccessibilityPermission.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  AXIsProcessTrustedWithOptions check + Settings deep link
//
//  Thin wrapper around real OS permission APIs — not unit tested, since
//  calling it for real would either trigger a system prompt or open System
//  Settings on the developer's machine.

import AppKit
import ApplicationServices

enum AccessibilityPermission {
    /// Checks whether Accessibility access is granted. When `prompt` is true,
    /// macOS shows its own "add Puck to Accessibility" system prompt if not.
    static func isTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Deep link to System Settings > Privacy & Security > Accessibility, for
    /// re-prompting a user who dismissed the initial system prompt.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
