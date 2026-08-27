//
//  TankResidency.swift
//  Puck
//
//  Where the pet's tank is, how big it was when it said so, and the two
//  sizes a trip between the tank and the desktop is between.
//
//  Five things, four of them properties on the app delegate and the fifth a
//  mutable static beside them -- all read and written by one file. Together
//  they are one idea: the pet is either out on the desktop or in a glass box
//  somewhere, and the box has a size that decides how big the pet is while it
//  is in there.
//
//  `scale(for:)` is the part worth pinning. The height a person asks for is
//  not always the height they get: a tank has to be two pets across before it
//  is worth standing in, so a narrow window's island sizes the pet down --
//  and the alternative is pet-app refusing the area outright, which from
//  outside looks like the pet ignoring the window.
//

import CoreGraphics

struct TankResidency {
    /// The tank in the overlay window's own coordinates, or nil when there is
    /// none to go to.
    var area: CGRect?

    /// The tank as the client last reported it. The size the pet travels at
    /// is worked out from this, so it is remembered before the area is.
    var lastReportedSize: CGSize?

    /// How tall the pet stands on the island, in points. Written by the lever
    /// on the island, over the bridge.
    ///
    /// A fixed height rather than a fraction of the size slider: the island is
    /// a fixed 90pt whoever is looking at it, so a relative scale made the pet
    /// fill it at one setting and rattle around in it at another. On the
    /// desktop the slider still decides.
    var petHeight: CGFloat = defaultPetHeight

    /// The avatar scale the pet had before it went home, for the trip back
    /// out. There is no stored setting to read it back from -- the size
    /// slider hands a scale straight in and nothing keeps it.
    var desktopScale: Double = 1

    /// The size a trip in progress is heading for, so a drag during the
    /// flight home lands at the size that was chosen rather than the one
    /// chosen before it. The trip lerps toward this every frame; writing the
    /// scale directly would just be overwritten by the next.
    var travelTargetScale: Double = 1

    static let defaultPetHeight: CGFloat = 72

    /// The scale that puts the pet at `petHeight` -- or at whatever the tank
    /// can actually hold, when that is less.
    ///
    /// 1 when there is no avatar yet, which happens before one is installed
    /// and never while a move is running.
    func scale(forPetOfSize base: CGSize) -> Double {
        guard base.height > 0 else { return 1 }
        guard let lastReportedSize, base.width > 0 else {
            return Double(petHeight / base.height)
        }
        let fitted = PetTankArea.fittedPetHeight(
            desired: petHeight,
            tank: lastReportedSize,
            aspect: base.width / base.height
        )
        return Double(fitted / base.height)
    }
}
