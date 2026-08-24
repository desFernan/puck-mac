//
//  GlobalScreenSpace.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Normalizes every NSScreen into a single top-left origin space, absorbing
//  the AppKit/CGWindowList origin difference.
//

import CoreGraphics

/// Absorbs the coordinate-space difference between AppKit (NSScreen, bottom-left
/// origin, Y increases upward) and CGWindowList/Quartz (top-left origin, Y
/// increases downward) in one place. Movement, window tracking, and hitboxes
/// all operate purely in this normalized space.
///
/// The conversion is anchored to **the primary display's height**
/// (NSScreen.screens[0], always at origin (0,0)) — not the bounding box of
/// every screen — because Quartz's global origin is always the primary
/// display's top-left corner.
struct GlobalScreenSpace: Equatable {
    /// AppKit frames in NSScreen.screens order. screens[0] is always at origin
    /// (0,0) per AppKit convention.
    let appKitFrames: [CGRect]

    /// Fails when `appKitFrames` is empty (e.g. NSScreen.screens can return an
    /// empty array while every display is asleep/detached) — there is no
    /// primary-screen height to anchor the Y flip to, and silently defaulting
    /// it to 0 would flip every Y coordinate's sign instead of failing loudly.
    init?(appKitFrames: [CGRect]) {
        guard !appKitFrames.isEmpty else { return nil }
        self.appKitFrames = appKitFrames
    }

    private var primaryScreenHeight: CGFloat {
        // appKitFrames is guaranteed non-empty by the failable init.
        appKitFrames[0].height
    }

    /// AppKit global coordinate -> normalized coordinate (top-left origin, Y increases downward)
    func normalized(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Normalized coordinate -> AppKit global coordinate (inverse; the Y flip
    /// makes the formula symmetric)
    func appKitPoint(fromNormalized point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Every display frame converted to the normalized space (used for boundary
    /// crossing / window-tracking checks)
    var normalizedScreenFrames: [CGRect] {
        appKitFrames.map { frame in
            let topLeft = normalized(fromAppKit: CGPoint(x: frame.minX, y: frame.maxY))
            return CGRect(origin: topLeft, size: frame.size)
        }
    }

    /// Bounding box of every display combined, in the normalized space
    var bounds: CGRect {
        normalizedScreenFrames.reduce(CGRect.null) { $0.union($1) }
    }
}

#if canImport(AppKit)
import AppKit

extension GlobalScreenSpace {
    /// Builds one from the currently connected display configuration
    /// (Overlay/ScreenManager re-calls this on didChangeScreenParametersNotification).
    /// Returns nil if NSScreen.screens is momentarily empty — callers should
    /// keep their last-known GlobalScreenSpace rather than treat this as (0,0).
    static func current() -> GlobalScreenSpace? {
        GlobalScreenSpace(appKitFrames: NSScreen.screens.map(\.frame))
    }
}
#endif
