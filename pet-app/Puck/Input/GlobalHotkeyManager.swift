//
//  GlobalHotkeyManager.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  CGEvent.tapCreate-based global hotkey capture (requires Accessibility permission)
//
//  Requires Accessibility permission (AccessibilityPermission.swift, F4) —
//  tapCreate returns nil without it. Never swallows events (always passes
//  the original event through) since these combos aren't reserved system
//  shortcuts; Puck should react to them without stopping them from also
//  reaching whatever app is frontmost.

import CoreGraphics
import Foundation

/// What a raw key event should result in, given the current bindings and
/// whether PTT is currently held. Pure — no CGEvent tap needed to test it.
enum HotkeyAction: Equatable {
    case pushToTalkDown
    case pushToTalkUp
    case textInputRequested
    case characterSummonRequested
    case toySummon1Requested
    case toySummon2Requested
    case none
}

enum HotkeyDecisionMaker {
    static func decide(
        eventType: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        bindings: HotkeyBindings,
        isPushToTalkActive: Bool
    ) -> HotkeyAction {
        switch eventType {
        case .keyDown:
            // Nothing else happens while push-to-talk holds that key. The OS
            // re-sends keyDown for a physically held key, with whatever
            // modifiers are down *now* -- so a hold on Space with Shift added
            // halfway through fell past this and matched the text-input
            // binding, opening the capture panel on top of a live recording.
            // Matched on the key alone, like the release below.
            if isPushToTalkActive, bindings.pushToTalk.keyCode == keyCode {
                return .none
            }
            if bindings.pushToTalk.matches(keyCode: keyCode, modifierFlags: flags) {
                return .pushToTalkDown
            }
            if bindings.textInput.matches(keyCode: keyCode, modifierFlags: flags) {
                return .textInputRequested
            }
            if bindings.characterSummon.matches(keyCode: keyCode, modifierFlags: flags) {
                return .characterSummonRequested
            }
            if bindings.toySummon1.matches(keyCode: keyCode, modifierFlags: flags) {
                return .toySummon1Requested
            }
            if bindings.toySummon2.matches(keyCode: keyCode, modifierFlags: flags) {
                return .toySummon2Requested
            }
            return .none

        case .keyUp:
            guard isPushToTalkActive, bindings.pushToTalk.keyCode == keyCode else { return .none }
            return .pushToTalkUp

        case .flagsChanged:
            // Handles releasing the modifier (e.g. Option) before the key
            // (Space) during a PTT hold — there's no keyUp for Space yet in
            // that case, so this is the only signal that the hold ended.
            guard isPushToTalkActive else { return .none }
            let relevant = HotkeyBinding.relevantModifierMask
            let stillHeld = flags.intersection(relevant).isSuperset(of: bindings.pushToTalk.modifierFlags.intersection(relevant))
            return stillHeld ? .none : .pushToTalkUp

        default:
            return .none
        }
    }
}

final class GlobalHotkeyManager {
    var bindings: HotkeyBindings
    private var isPushToTalkActive = false

    /// Fired on keyDown/keyUp for the PTT combo (hold-to-talk).
    var onPushToTalkDown: (() -> Void)?
    var onPushToTalkUp: (() -> Void)?
    /// Fired on keyDown for the one-shot combos.
    var onTextInputRequested: (() -> Void)?
    var onCharacterSummonRequested: (() -> Void)?
    var onToySummon1Requested: (() -> Void)?
    var onToySummon2Requested: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    init(bindings: HotkeyBindings = .defaults) {
        self.bindings = bindings
    }

    /// Returns false if the event tap couldn't be created (most commonly:
    /// Accessibility permission not granted).
    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { proxy, type, event, refcon in
                    // Unretained: this tap only listens, so the event is
                    // handed straight back and its ownership never changes.
                    // Retaining it leaked one CGEvent per key the user
                    // pressed, for the life of the app.
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    // macOS switches a tap off if it is slow to answer, or
                    // when the user's own input storms it. Nothing turned it
                    // back on, so every global hotkey stayed dead for the
                    // rest of the session -- and the pet's push-to-talk with
                    // them.
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        manager.reEnableTap()
                        return Unmanaged.passUnretained(event)
                    }
                    _ = proxy
                    manager.handle(type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        let currentRunLoop = CFRunLoopGetCurrent()
        runLoop = currentRunLoop
        CFRunLoopAddSource(currentRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// The tap holds this object unretained -- it has to, or the manager
    /// could never be released -- so the tap must not outlive it. Without
    /// this, an owner that simply drops the manager leaves a live tap calling
    /// into freed memory on the next keystroke.
    deinit {
        stop()
    }

    /// Removes the source from the same run loop start() added it to --
    /// CFRunLoopGetCurrent() at stop() time isn't guaranteed to be the same
    /// run loop if this were ever called from a different thread/context.
    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource, let runLoop {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
    }

    /// Turns the tap back on after macOS switched it off. Called from the tap
    /// callback, which is the only place that hears about it.
    fileprivate func reEnableTap() {
        guard let eventTap else { return }
        AppLogger.shared.log(.warning, "GlobalHotkeyManager: the event tap was disabled; re-enabling it")
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let action = HotkeyDecisionMaker.decide(
            eventType: type,
            keyCode: keyCode,
            flags: event.flags,
            bindings: bindings,
            isPushToTalkActive: isPushToTalkActive
        )

        switch action {
        case .pushToTalkDown:
            isPushToTalkActive = true
            onPushToTalkDown?()
        case .pushToTalkUp:
            isPushToTalkActive = false
            onPushToTalkUp?()
        case .textInputRequested:
            onTextInputRequested?()
        case .characterSummonRequested:
            onCharacterSummonRequested?()
        case .toySummon1Requested:
            onToySummon1Requested?()
        case .toySummon2Requested:
            onToySummon2Requested?()
        case .none:
            break
        }
    }
}
