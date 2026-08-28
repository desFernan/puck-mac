//
//  AudioActivity.swift
//  Puck
//
//  Which apps are making a sound right now.
//
//  CoreAudio's process list, which is public and needs no permission, unlike
//  the system's now-playing information -- that lives behind an entitlement
//  Apple does not hand out, and asking for it without one returns an empty
//  answer rather than an error.
//
//  This is what lets the panel notice a browser. A browser cannot be asked
//  what it is playing, but it can be caught playing something, and that is
//  enough to know which window to read a title from.
//

import AppKit
import CoreAudio
import Foundation

enum AudioActivity {
    /// The bundle identifiers of everything currently sending audio out.
    ///
    /// Helpers included, not folded into their parent: a browser plays
    /// through a renderer process with its own identifier, and which of the
    /// two shows up varies by browser. Callers match by prefix instead.
    static func appsMakingSound() -> Set<String> {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects
        ) == noErr else { return [] }

        var making: Set<String> = []
        for object in objects where isRunningOutput(object) {
            guard let pid = pid(of: object),
                  let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            else { continue }
            making.insert(bundle)
        }
        return making
    }

    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr
        else { return nil }
        return pid
    }
}
