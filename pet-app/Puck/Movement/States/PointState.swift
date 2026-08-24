//
//  PointState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Point state's StateHandler implementation
//
//  Holds the point clip while F10's PointingController runs the release
//  timer (8s, or sooner if the target gets clicked). This state deliberately
//  owns neither the timer nor the target: the tool call that started the
//  pointing needs to be told the moment Point begins (protocol section 4),
//  and that wiring lives at bootstrap alongside PointingController.
//

import Foundation

final class PointState: StateHandler {
    let name = "Point"
    let clipKey = "point"
    let loopsClip = true

    /// Fired when the pet actually starts pointing.
    var onEnter: (() -> Void)?

    func enter() {
        onEnter?()
    }
}
