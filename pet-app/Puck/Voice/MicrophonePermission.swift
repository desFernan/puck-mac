//
//  MicrophonePermission.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Microphone/speech recognition permission request wrapper
//
//  Thin wrapper around real OS permission APIs — not unit tested, since
//  calling it for real triggers an actual system prompt on the developer's
//  machine (same reasoning as AccessibilityPermission, F4).

import AVFoundation
import Speech

enum MicrophonePermission {
    /// `@Sendable`: AVFoundation calls back on an arbitrary queue, which is
    /// exactly why the callers hop to the main thread themselves.
    static func requestMicrophoneAccess(completion: @escaping @Sendable (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// `@Sendable` for the same reason as the microphone above.
    static func requestSpeechRecognitionAccess(completion: @escaping @Sendable (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                completion(status == .authorized)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
}
