//
//  VoiceInputController.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Single class owning both the PTT key event and the recording lifecycle
//

import Foundation

/// What VoiceInputController needs from F7's speech recognition — kept as a
/// protocol so this class is testable without a real mic/Speech framework.
protocol SpeechRecognitionServicing: AnyObject {
    var onPartialResult: ((String) -> Void)? { get set }
    var onFinalResult: ((String) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    func startStreaming()
    func stopStreaming()
}

/// Owns the PTT key event and the recording lifecycle together (deliberate
/// single-owner design, F7). Holds shorter than
/// `minimumHoldDuration` still occupy the mic for their (brief) duration —
/// "마이크 점유는 홀드 구간 한정" — but their eventual final transcription is
/// discarded rather than submitted, treating them as an accidental tap.
final class VoiceInputController {
    static let minimumHoldDuration: TimeInterval = 0.3

    private let speechService: SpeechRecognitionServicing
    private let now: () -> TimeInterval
    /// Whether the microphone and speech recognition have both been granted,
    /// and how to ask. Injected rather than called directly so this class
    /// stays testable without AVFoundation and without triggering a real
    /// system prompt on whoever runs the tests.
    private let hasVoicePermissions: () -> Bool
    private let requestVoicePermissions: () -> Void
    private var hasAskedForVoicePermissions = false
    private var pressStartUptime: TimeInterval?
    private var heldLongEnough = false
    /// Whether a hold is actually recording. Read by the bridge so the chat
    /// window's mic button can show the truth: a press with no speech
    /// permission spends itself on the prompt and records nothing, and a
    /// button that lights up anyway is a button that lies.
    private(set) var isListening = false

    /// Enter Listen state + listen_start SFX (F3/F5's responsibility to react to this).
    var onListenStart: (() -> Void)?
    /// Return to whichever state was active before Listen.
    var onListenEnd: (() -> Void)?
    /// Live captions shown in the text bubble while holding.
    var onPartialText: ((String) -> Void)?
    /// The submitted transcription — protocol 3.3 user_input(source: "voice").
    var onFinalText: ((String) -> Void)?
    /// Speech-service errors (e.g. recognizer unavailable, audio engine
    /// failed to start) -- previously dropped silently, leaving the FSM
    /// stuck in ListenState with no feedback until a manual key release.
    var onError: ((Error) -> Void)?

    init(
        speechService: SpeechRecognitionServicing,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        hasVoicePermissions: @escaping () -> Bool = { PermissionOnboarding.hasVoicePermissions() },
        requestVoicePermissions: @escaping () -> Void = { PermissionOnboarding.requestVoicePermissions() }
    ) {
        self.speechService = speechService
        self.now = now
        self.hasVoicePermissions = hasVoicePermissions
        self.requestVoicePermissions = requestVoicePermissions
        speechService.onPartialResult = { [weak self] text in self?.onPartialText?(text) }
        speechService.onFinalResult = { [weak self] text in
            guard self?.heldLongEnough == true else { return }
            self?.onFinalText?(text)
        }
        speechService.onError = { [weak self] error in
            guard let self else { return }
            self.onError?(error)
            if self.isListening {
                // The engine and its input tap do not stop themselves when a
                // recognition fails. Clearing the flag alone left the
                // microphone held for the rest of the session -- and the
                // release that follows takes the `guard isListening` exit, so
                // nothing else was ever going to stop it either.
                self.speechService.stopStreaming()
                self.isListening = false
                self.pressStartUptime = nil
                self.onListenEnd?()
            }
        }
    }

    /// Idempotent -- defense in depth alongside GlobalHotkeyManager's own
    /// key-repeat guard. A duplicate down while already active must not
    /// slide the hold-start time forward or restart streaming.
    func pushToTalkDown() {
        guard !isListening else { return }
        // The first hold is where the microphone is asked for. Asking at
        // launch instead meant a dialog on the desktop for everyone, every
        // time the app was rebuilt, whether or not they ever speak to the pet
        // -- see AppDelegate.requestPermissions.
        //
        // The press that triggers the prompt is spent on the prompt: the
        // stream cannot start until it is answered, and by then the key is
        // long since up. Every hold after it records.
        guard requestVoicePermissionsIfNeeded() else { return }
        isListening = true
        pressStartUptime = now()
        heldLongEnough = false
        onListenStart?()
        speechService.startStreaming()
    }

    /// - Returns: whether recording can start now. False while a prompt is on
    ///   screen, and false for good once the answer is no.
    private func requestVoicePermissionsIfNeeded() -> Bool {
        guard !hasVoicePermissions() else { return true }
        guard !hasAskedForVoicePermissions else { return false }
        hasAskedForVoicePermissions = true
        requestVoicePermissions()
        return false
    }

    func pushToTalkUp() {
        guard isListening else { return }
        isListening = false
        defer { pressStartUptime = nil }
        if let start = pressStartUptime, now() - start >= Self.minimumHoldDuration {
            heldLongEnough = true
        }
        speechService.stopStreaming()
        onListenEnd?()
    }
}
