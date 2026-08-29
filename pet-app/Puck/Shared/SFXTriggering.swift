//
//  SFXTriggering.swift
//  Puck
//
//  What the state machine asks of a sound player.
//
//  Here rather than beside CharacterController, which declared it. Declaring
//  a protocol next to its *caller* rather than to its implementor puts the
//  implementor -- Audio's SFXPlayer -- in the position of reaching up into
//  the movement engine to find out what shape it has to be, which is exactly
//  backwards: the whole reason this protocol exists is so the FSM need not
//  know about the concrete player.
//

/// The minimal interface Audio's SFXPlayer implements, so the FSM need not
/// know about the concrete player.
protocol SFXTriggering: AnyObject {
    /// Triggers the sound mapped to an FSM clip key or socket event name key
    /// (silent if the manifest's sounds table has no match). `loop` mirrors
    /// AvatarPlayable.play(clip:loop:) — a looping trigger (e.g. "walk")
    /// keeps playing until a *different* loop key is triggered, at which
    /// point F5 fades the old one out ("루프 사운드(walk)는
    /// 상태 유지 중 반복, exit()에서 페이드아웃"). One-shot (loop: false)
    /// triggers (react_click, task_success, ...) never interrupt a loop.
    func trigger(_ key: String, loop: Bool)
}
