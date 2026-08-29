//
//  SpeechRecognitionService.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  SFSpeechAudioBufferRecognitionRequest streaming, on-device first / server fallback
//
//  "On-device first, server fallback" is decided upfront via
//  SFSpeechRecognizer.supportsOnDeviceRecognition rather than reactively
//  retrying after an on-device failure — reactive retry would need to
//  pattern-match specific SFSpeechRecognizer error cases that aren't cleanly
//  documented/stable across macOS versions, so this is the more robust
//  interpretation of the plan's intent.

import Speech
import AVFoundation

/// Started and stopped from the main thread -- push-to-talk arrives on the
/// main run loop's event tap -- and every callback it makes is hopped back
/// there, because what they drive is the character, the SFX player and the
/// speech bubble. Speech's own completion handler makes no promise about
/// which thread it uses.
final class SpeechRecognitionService: SpeechRecognitionServicing {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Bumped on every startStreaming() -- lets a still-in-flight previous
    /// session's completion closure (endAudio() lets it finish naturally
    /// rather than being cancelled) detect it's been superseded and ignore
    /// its late result instead of misdelivering it into the new session.
    private var generation = 0

    /// Defaults to the system locale (ko-KR on a Korean system), per F7
    /// ("언어: 시스템 로케일(ko-KR) 기본, 설정 변경").
    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func startStreaming() {
        guard let recognizer, recognizer.isAvailable else {
            onError?(SpeechRecognitionServiceError.recognizerUnavailable)
            return
        }

        if recognitionRequest != nil {
            // A previous session's endAudio() was never sent (startStreaming
            // called again without an intervening stopStreaming) -- force it
            // closed now instead of silently leaking it.
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
        }

        generation += 1
        let sessionGeneration = generation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        // The request itself, not the property holding it: this block runs on
        // the audio IO thread, and reading a property that startStreaming and
        // stopStreaming write on the main thread is a race on the reference.
        // Appending to a request that has already had endAudio() is ignored,
        // so a tap that outlives its session by a buffer is harmless.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onError?(error)
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Onto the main thread before anything else. Speech does not say
            // which thread it calls this on, and everything downstream --
            // the character's state, the SFX player, the bubble -- belongs to
            // the main one. `generation` is only ever touched here and in the
            // two methods above, which the main thread also owns.
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                // A short discarded tap's real final result can arrive after a
                // subsequent hold has already started a new session --
                // generation stops it from being misdelivered as that
                // session's result.
                guard let self, self.generation == sessionGeneration else { return }
                if let transcript {
                    if isFinal {
                        self.onFinalResult?(transcript)
                        self.recognitionTask = nil
                    } else {
                        self.onPartialResult?(transcript)
                    }
                }
                if let error {
                    self.onError?(error)
                    self.recognitionTask = nil
                }
            }
        }
    }

    func stopStreaming() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        // endAudio() (not cancel()) lets the task finish transcribing
        // already-buffered audio and deliver its real final result through
        // the completion closure above -- cancelling here aborted it first.
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }
}

enum SpeechRecognitionServiceError: Error, Equatable {
    case recognizerUnavailable
}
