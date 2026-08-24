//
//  PermissionOnboarding.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  TCC permission self-check + re-prompt UI (Accessibility/microphone/speech recognition/screen recording)
//
//  Addresses the risk in plan/02_pet-app.md section 6 (CGEvent tap
//  permission can reset on a macOS update) by giving the app a single place
//  to check + re-prompt at any time, not just at first launch.

import AVFoundation
import Speech

struct PermissionStatus: Equatable {
    let accessibility: Bool
    let microphone: Bool
    let speechRecognition: Bool

    var allGranted: Bool { accessibility && microphone && speechRecognition }
}

enum PermissionOnboarding {
    /// Snapshot of current permission state. Never prompts.
    static func currentStatus() -> PermissionStatus {
        PermissionStatus(
            accessibility: AccessibilityPermission.isTrusted(prompt: false),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized
        )
    }

    /// Requests whichever of mic/speech-recognition permissions haven't been
    /// decided yet (first run). Accessibility can't be silently requested by
    /// an app — only prompted via AccessibilityPermission.isTrusted(prompt:
    /// true) or by sending the user to the System Settings deep link
    /// (AccessibilityPermission.openSystemSettings()).
    /// Both of the ones voice input needs, as one answer -- transcription
    /// takes a recording *and* permission to recognise it, so either missing
    /// means push-to-talk cannot work.
    static func hasVoicePermissions() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Asks for both, in order. Called the first time push-to-talk is held
    /// rather than at launch: a locally-signed app's grants are pinned to the
    /// exact binary, so asking at launch put a microphone dialog on the
    /// desktop after every rebuild, for everyone, whether or not they ever
    /// use voice.
    static func requestVoicePermissions() {
        MicrophonePermission.requestMicrophoneAccess { _ in
            MicrophonePermission.requestSpeechRecognitionAccess { _ in }
        }
    }

    static func requestUndecidedPermissions(completion: @escaping (PermissionStatus) -> Void) {
        MicrophonePermission.requestMicrophoneAccess { _ in
            MicrophonePermission.requestSpeechRecognitionAccess { _ in
                completion(currentStatus())
            }
        }
    }
}
