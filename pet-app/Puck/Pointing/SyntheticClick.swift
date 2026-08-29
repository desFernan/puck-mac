//
//  SyntheticClick.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  click_element: synthesizes CGEvent mouse down/up, detects not_supported_target
//
//  Design premise (F10): clicking on behalf of the user
//  on a system security dialog is not something WindowServer policy allows
//  regardless of what this code does — guiding the user there via point_at
//  is the actual limit of what's supported. Classifying "is this target a
//  system dialog" needs F4 level 2 (UIElementInspector, AX role/owner
//  inspection), which doesn't exist yet — ClickElementHandler (F11) is
//  responsible for that classification and for returning not_supported_target;
//  this type only performs the synthesis once told to.

import CoreGraphics

enum SyntheticClick {
    /// Synthesizes a left-click (mouseDown immediately followed by mouseUp)
    /// at `point` (global screen coordinates, CGWindowList/Quartz space).
    /// Approval is the agent core's gate (protocol section 4); this only executes.
    static func click(at point: CGPoint) {
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
