//
//  ToyCatalogue.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The toys the pet can be given, and how big each one is drawn.
//
//  Toys live in the app bundle, one directory each under `Resources/Toys/`,
//  mirroring how avatar packages are laid out -- a flat pile of PNGs stops
//  telling you what
//  belongs to what as soon as a toy needs more than one file.
//
//  Only a HEIGHT is configured, never a width: the width follows from the
//  artwork's own proportions at load time. The toy layer used to be square,
//  which was invisible while the only toy was a round pumpkin and quite
//  wrong for the wand -- 310x804 art fitted into a square box renders about
//  17pt wide, a sliver. Sizing the layer to the art means no letterboxing at
//  all, so the visible outline matches the layer and everything measured
//  from it (floors, walls, head collisions, where the pet stands) stays true.
//

import CoreGraphics
import Foundation

/// How the pet plays with a toy once it has walked over to it. Different
/// toys want genuinely different behaviour -- a pumpkin is for throwing and
/// catching, a wand is for twirling -- and which one it is belongs to the toy rather
/// than to the state that carries it out.
enum ToyPlayStyle: Equatable {
    /// Thrown up over the pet's head, caught, thrown again.
    case throwAndCatch
    /// Held spinning above the pet's head.
    case spinOverhead
}

struct Toy: Equatable {
    /// Directory *and* file stem under `Resources/Toys/`, i.e.
    /// `Toys/<name>/<name>.png`.
    let name: String
    /// On-screen height in points at scale 1. Width comes from the artwork.
    let height: CGFloat
    /// What the pet does with it.
    let play: ToyPlayStyle
}

enum ToyCatalogue {
    /// Round and chunky; the original toy.
    static let pumpkin = Toy(name: "pumpkin", height: 44, play: .throwAndCatch)
    /// Tall and thin -- 0.27 as wide as it is tall once straightened -- so it
    /// needs considerably more height than the pumpkin to have any presence
    /// at all. At this height it draws about 24pt across.
    static let wand = Toy(name: "wand", height: 88, play: .spinOverhead)

    static let all: [Toy] = [pumpkin, wand]

    static let `default` = pumpkin

    /// Falls back to the default rather than failing: the stored setting is
    /// just a string, and a toy that has been renamed or removed shouldn't
    /// leave the user with no toy and no way to pick one.
    static func toy(named name: String) -> Toy {
        all.first { $0.name == name } ?? `default`
    }
}
