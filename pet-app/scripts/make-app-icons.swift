#!/usr/bin/env swift
//
//  make-app-icons.swift
//  Puck
//
//  Turns one square export into both apps' icon sets, and the menu bar's.
//
//  macOS does not round app icons for you the way iOS does -- whatever is in
//  the asset is exactly what the Dock draws, so a square export shows up as a
//  tile next to every other app's squircle. Big Sur's grid puts the rounded
//  content in the middle 824/1024 of the canvas with a ~185px corner radius
//  and leaves the rest transparent for the shadow.
//
//  Swift rather than the Pillow script beside it: this machine's python has no
//  PIL, and AppKit draws rounded rectangles and writes PNGs without anything
//  to install.
//
//  Usage: swift scripts/make-app-icons.swift <source.png>
//

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2, let source = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: make-app-icons.swift <source.png>\n".utf8))
    exit(2)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Puck/Resources/Assets.xcassets")

/// The canvas an icon is drawn on, with the art inset and rounded the way
/// every other macOS app's is.
func iconCanvas(size: CGFloat) -> NSImage {
    let content = size * 824 / 1024
    let radius = size * 185 / 1024
    let offset = (size - content) / 2
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let box = NSRect(x: offset, y: offset, width: content, height: content)
    // The drop shadow every macOS icon sits on: without it a pale icon looks
    // pasted onto the Dock rather than resting on it.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = size * 12 / 1024
    shadow.shadowOffset = NSSize(width: 0, height: -size * 10 / 1024)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    let clip = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    clip.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    source.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    image.unlockFocus()
    return image
}

/// A circle of the art, for the menu bar. The bar draws exactly what it is
/// given, and a square picture in a row of system glyphs reads as a sticker
/// somebody stuck there; a circle reads as somebody's face, which is what it
/// is. Drawn large and scaled down so the edge is not stair-stepped.
func circularCanvas(size: CGFloat) -> NSImage {
    let supersample: CGFloat = 8
    let big = size * supersample
    let image = NSImage(size: NSSize(width: big, height: big))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: big, height: big)).addClip()
    source.draw(
        in: NSRect(x: 0, y: 0, width: big, height: big),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    image.unlockFocus()
    return resized(image, to: size)
}

func write(_ image: NSImage, to url: URL) {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("error: could not encode \(url.lastPathComponent)\n".utf8))
        exit(1)
    }
    try? png.write(to: url)
    print("\(url.lastPathComponent): \(Int(image.size.width))px")
}

// Both apps' icon sets, the ten entries their Contents.json already declares.
for set in ["AppIcon.appiconset", "AppIconClient.appiconset"] {
    let directory = assets.appendingPathComponent(set)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = CGFloat(size * scale)
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            write(resized(iconCanvas(size: 1024), to: pixels), to: directory.appendingPathComponent(name))
        }
    }
}

/// Drawn once at full size and scaled down, rather than drawn at each size:
/// a 16px canvas has no room for the shadow's blur, and the corner radius
/// rounds to nothing.
func resized(_ image: NSImage, to size: CGFloat) -> NSImage {
    let out = NSImage(size: NSSize(width: size, height: size))
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    out.unlockFocus()
    return out
}

// The menu bar's, at the three scales AppKit may ask for.
let menuBar = assets.appendingPathComponent("MenuBarIcon.imageset")
try? FileManager.default.createDirectory(at: menuBar, withIntermediateDirectories: true)
for (name, size) in [("icon.png", 18.0), ("icon@2x.png", 36.0), ("icon@3x.png", 54.0)] {
    write(circularCanvas(size: size), to: menuBar.appendingPathComponent(name))
}
try? Data("""
{
  "images": [
    { "idiom": "universal", "scale": "1x", "filename": "icon.png" },
    { "idiom": "universal", "scale": "2x", "filename": "icon@2x.png" },
    { "idiom": "universal", "scale": "3x", "filename": "icon@3x.png" }
  ],
  "info": { "author": "xcode", "version": 1 }
}

""".utf8).write(to: menuBar.appendingPathComponent("Contents.json"))
