//
//  WindowInfo.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Normalized window info model {role,title,frame,...}
//

import CoreGraphics

/// A window as reported by CGWindowListCopyWindowInfo, normalized into
/// GlobalScreenSpace's coordinate system. `frame` is expected to already be
/// in that normalized (top-left origin, Y-down) space.
struct WindowInfo: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String?
    let title: String?
    /// kCGWindowLayer. Normal app windows are layer 0; only those are relevant
    /// for landing-surface/tracking purposes.
    let layer: Int
    let frame: CGRect
}
