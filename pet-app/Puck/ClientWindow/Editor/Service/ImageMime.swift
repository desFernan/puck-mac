//
//  ImageMime.swift
//  Puck
//
//  Swift port of workspace/src/shared/image-mime.ts.
//

import Foundation

enum ImageMime {
    static let extensionMap: [String: String] = [
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".webp": "image/webp",
    ]

    /// Detects the real image format from magic bytes -- an extension alone
    /// can't catch a spoofed file.
    static func detect(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 8, Array(bytes[0..<8]) == [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] {
            return "image/png"
        }
        if bytes.count >= 3, bytes[0] == 0xff, bytes[1] == 0xd8, bytes[2] == 0xff {
            return "image/jpeg"
        }
        if bytes.count >= 6, let header = String(bytes: bytes[0..<6], encoding: .ascii),
           header == "GIF87a" || header == "GIF89a" {
            return "image/gif"
        }
        if bytes.count >= 12,
           let riff = String(bytes: bytes[0..<4], encoding: .ascii), riff == "RIFF",
           let webp = String(bytes: bytes[8..<12], encoding: .ascii), webp == "WEBP" {
            return "image/webp"
        }
        return nil
    }
}
