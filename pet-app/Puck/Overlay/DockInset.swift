//
//  DockInset.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  How much of a screen's bottom edge the Dock occupies, from NSScreen's own
//  frame/visibleFrame difference -- used to keep roamableArea's ground line
//  above the Dock instead of exactly on top of it (the Dock's window level
//  is higher than our overlay's, so standing exactly at the screen's literal
//  bottom edge renders the pet's lower half underneath the Dock).
//
//  Deliberately not used to change GlobalScreenSpace/window frames
//  themselves -- that model's Y-flip math depends on the primary screen's
//  frame starting at (0,0), which visibleFrame doesn't guarantee.
//

import CoreGraphics

enum DockInset {
    static func bottomInset(screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
        max(0, visibleFrame.minY - screenFrame.minY)
    }
}
