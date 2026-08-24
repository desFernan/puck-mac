//
//  TypeState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Type state's StateHandler implementation
//
//  Entered directly on a code_editor tool_call event (any current state can
//  be interrupted into this) -- NOT via MoveTo(editor window): the protocol's
//  code_editor detail only ever carries a file path ({"path": "src/main.ts"}),
//  never window coordinates, so there is nothing for F4 to walk the pet
//  toward (02_pet-app.md F3 corrected to match, found via spec cross-check).
//
//  The typing SFX loop needs nothing state-specific -- it already gets it for
//  free from CharacterController.enterCurrentState's generic
//  sfxPlayer.trigger(clipKey, loop: loopsClip) call, same as every other
//  looping state (walk's footsteps). The "short hop on detail.path changes"
//  lives in EventRouter/BridgeMessageRouter instead (path-change tracking
//  is response-routing knowledge, not something this state needs to know).

final class TypeState: StateHandler {
    let name = "Type"
    let clipKey = "type"
    let loopsClip = true
}
