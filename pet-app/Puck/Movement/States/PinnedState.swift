//
//  PinnedState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Pinned state's StateHandler implementation.
//
//  Entered when Option+Shift+Space summons the F13 client window -- the
//  character should hold still with the input panel beside it. Like Listen
//  (F7), this is a trivial pass-through -- the "capture current state, enter
//  Pinned, restore on close" logic lives in AppDelegate (see stateBeforePin),
//  not here. No dedicated manifest clip exists for this, so it reuses "idle"
//  (same convention as WalkOnTop/MoveTo reusing "walk", per StateHandler's
//  clipKey doc).
//
//  Not yet implemented: 02_pet-app.md F3 also calls for "창이 뜨는 쪽으로
//  살짝 도킹 이동" (a short move toward the client window's dock position) --
//  deferred until F13's real window (which knows where it opens) exists.
//  Wandering already stops simply by not being IdleState, same as
//  Listen/Type/Point.

final class PinnedState: StateHandler {
    let name = "Pinned"
    let clipKey = "idle"
    let loopsClip = true
}
