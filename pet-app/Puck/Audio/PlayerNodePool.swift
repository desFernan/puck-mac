//
//  PlayerNodePool.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Manages a pool of 4-8 concurrently playable PlayerNodes
//

import AVFoundation

/// Just the part of AVAudioPlayerNode the pool's selection logic needs —
/// lets the round-robin/idle-picking algorithm be tested with fakes instead
/// of real, engine-attached AVAudioPlayerNode instances.
protocol PooledAudioNode: AnyObject {
    var isPlaying: Bool { get }
}

extension AVAudioPlayerNode: PooledAudioNode {}

/// A fixed-size pool of nodes for concurrent one-shot/loop SFX playback
/// (plan/02_pet-app.md F5: "PlayerNode 풀(4~8개)로 동시 재생"). Prefers an
/// idle node; if every node is busy, falls back to round-robin reuse
/// (cutting off whichever node has been playing longest) rather than
/// dropping the new sound.
final class PlayerNodePool<Node: PooledAudioNode> {
    private let nodes: [Node]
    private var nextRoundRobinIndex = 0

    init(nodes: [Node]) {
        precondition(!nodes.isEmpty, "PlayerNodePool needs at least one node")
        self.nodes = nodes
    }

    /// - Parameter reserved: a node the caller is using for something that
    ///   must not be cut off -- the looping sound. Without it, a pool with
    ///   every node busy could round-robin onto the loop's own node, stop it
    ///   to play a one-shot, and leave the player still believing that loop
    ///   was running: `currentLoopKey` unchanged, so the same key would never
    ///   start it again.
    func nextAvailableNode(avoiding reserved: Node? = nil) -> Node {
        let candidates = nodes.filter { $0 !== reserved }
        // Only when the reserved node is the whole pool. Cutting it off is
        // still better than playing nothing.
        guard !candidates.isEmpty else { return nodes[0] }

        if let idle = candidates.first(where: { !$0.isPlaying }) {
            return idle
        }
        let node = candidates[nextRoundRobinIndex % candidates.count]
        nextRoundRobinIndex = (nextRoundRobinIndex + 1) % candidates.count
        return node
    }
}
