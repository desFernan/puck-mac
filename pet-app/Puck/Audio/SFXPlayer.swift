//
//  SFXPlayer.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Singleton SFX trigger API, AVAudioEngine-based
//

import AVFoundation

/// What a trigger(key:loop:) call should result in, given the sound table
/// lookup and whichever key is currently looping. Pure decision — no
/// AVFoundation dependency, fully testable independent of real audio.
enum SFXAction: Equatable {
    case silent
    case playOneShot(url: URL)
    case startLoop(url: URL)
    case alreadyLooping
}

enum SFXDecisionMaker {
    static func decide(key: String, loop: Bool, resolvedURL: URL?, currentLoopKey: String?) -> SFXAction {
        guard let url = resolvedURL else { return .silent }
        guard loop else { return .playOneShot(url: url) }
        guard key != currentLoopKey else { return .alreadyLooping }
        return .startLoop(url: url)
    }
}

/// AVAudioEngine-backed SFXTriggering implementation. Real audio I/O is not
/// unit tested (no fixture .wav files exist yet — see docs/avatar-spec.md);
/// SFXDecisionMaker and PlayerNodePool carry the tested logic, this class is
/// the thin, trusted execution layer over them.
final class SFXPlayer: SFXTriggering {
    private let engine: AVAudioEngine
    private let pool: PlayerNodePool<AVAudioPlayerNode>
    private let soundTable: SoundTable
    private var currentLoopKey: String?
    private var currentLoopNode: AVAudioPlayerNode?
    private var baseVolume: Float = 1.0

    /// Muting only guarded new trigger() calls, not an already-playing loop --
    /// driving both through the mixer's master output volume fixes that (a
    /// currently-looping walk cue goes silent immediately) and makes Settings'
    /// Volume/Mute toggles take effect live instead of only after a restart.
    var isMuted = false {
        didSet { applyOutputVolume() }
    }

    var volume: Float {
        get { baseVolume }
        set {
            baseVolume = newValue
            applyOutputVolume()
        }
    }

    private func applyOutputVolume() {
        engine.mainMixerNode.outputVolume = isMuted ? 0 : baseVolume
    }

    init(soundTable: SoundTable, poolSize: Int = 6) {
        self.soundTable = soundTable

        // Built against a local `engine` (not `self.engine`) so this closure
        // doesn't capture `self` before every stored property is initialized.
        let engine = AVAudioEngine()
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let nodes: [AVAudioPlayerNode] = (0..<poolSize).map { _ in
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            return node
        }

        self.engine = engine
        pool = PlayerNodePool(nodes: nodes)
        try? engine.start()
    }

    func trigger(_ key: String, loop: Bool) {
        guard !isMuted else { return }

        switch SFXDecisionMaker.decide(
            key: key,
            loop: loop,
            resolvedURL: soundTable.fileURL(for: key),
            currentLoopKey: currentLoopKey
        ) {
        case .silent, .alreadyLooping:
            return
        case .playOneShot(let url):
            // Never onto the looping node: stopping that one to play a click
            // would silence the loop while the player still thought it was
            // running.
            play(url: url, loop: false, node: pool.nextAvailableNode(avoiding: currentLoopNode))
        case .startLoop(let url):
            fadeOutCurrentLoop()
            let node = pool.nextAvailableNode()
            currentLoopKey = key
            currentLoopNode = node
            play(url: url, loop: true, node: node)
        }
    }

    /// Decoded once per file, then reused. trigger() runs on the frame loop
    /// (state entries, idle chatter), and a cold file open plus a full PCM
    /// decode on every fall/land/click does not fit a 16ms frame budget.
    private var bufferCache: [URL: AVAudioPCMBuffer] = [:]

    private func play(url: URL, loop: Bool, node: AVAudioPlayerNode) {
        guard let buffer = buffer(for: url) else { return }
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: loop ? [.loops] : [], completionHandler: nil)
        node.play()
    }

    private func buffer(for url: URL) -> AVAudioPCMBuffer? {
        if let cached = bufferCache[url] { return cached }
        guard
            let file = try? AVAudioFile(forReading: url),
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            (try? file.read(into: buffer)) != nil
        else {
            return nil
        }
        bufferCache[url] = buffer
        return buffer
    }

    private func fadeOutCurrentLoop() {
        // TODO(needs a real avatar/sound to tune against): a proper fade would
        // ramp this node's volume down over ~0.2s instead of an immediate stop.
        // AVAudioPlayerNode doesn't expose a per-node volume ramp directly —
        // this needs either a per-node AVAudioMixerNode tap or a manual timer-
        // driven volume step, deliberately not implemented blind.
        currentLoopNode?.stop()
        currentLoopNode = nil
        currentLoopKey = nil
    }
}
