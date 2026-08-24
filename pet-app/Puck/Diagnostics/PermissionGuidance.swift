//
//  PermissionGuidance.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Which permission a tool needs, and whether the pet should go and ask for
//  it -- surfacing the system permission dialog and having the pet point at
//  it with a speech bubble telling the user to click it.
//
//  A permission_denied used to reach the user as a sentence in the chat
//  transcript and nothing else -- which is the one place they are not
//  looking, since the thing they asked for visibly did not happen. The pet
//  is on screen, so it does the asking.
//
//  Pure decisions only: no prompting, no UI. AppDelegate owns both, because
//  putting up a system dialog from a unit test is not something to leave
//  possible.
//

import Foundation

enum PermissionGuidance {
    /// The permissions a tool can be blocked on. Only Accessibility today --
    /// mic and speech recognition gate PTT rather than a tool, and macOS
    /// grants those through their own request APIs rather than a settings
    /// pane the user has to be walked to.
    enum Permission: Equatable {
        case accessibility
    }

    /// What `tool` needs granted before it can work at all, if anything.
    ///
    /// `point_at` is deliberately absent: pointing is the pet walking across
    /// its own overlay, which needs nothing -- and it is the fallback the
    /// system-dialog rule (protocol section 4) leans on, so it must keep
    /// working precisely when Accessibility does not.
    static func permission(requiredBy tool: String) -> Permission? {
        switch tool {
        // Reads another app's AX tree.
        case "find_ui_element":
            return .accessibility
        // Posts a synthetic CGEvent into another app.
        case "click_element":
            return .accessibility
        default:
            return nil
        }
    }

    /// Whether a failed tool call should turn into pet-led guidance.
    ///
    /// Only for a permission that is actually missing: a tool can fail with
    /// permission_denied for reasons a prompt won't fix (a sandboxed target,
    /// a revoked grant macOS hasn't re-evaluated), and guiding the user to
    /// grant something they already granted is worse than saying nothing.
    static func shouldGuide(tool: String, isGranted: (Permission) -> Bool) -> Permission? {
        guard let permission = permission(requiredBy: tool), !isGranted(permission) else { return nil }
        return permission
    }
}
