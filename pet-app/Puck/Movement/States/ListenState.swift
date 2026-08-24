//
//  ListenState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Listen state's StateHandler implementation
//
//  Entered on PTT keyDown from any current state; on keyUp, returns to
//  whichever state was active before (F7 VoiceInputController owns that).
//  The plan's listen_start SFX (F7: "Listen 진입(listen 클립 + listen_start
//  SFX)") is an event-name sound key, not this state's clip key -- it's
//  triggered where Listen entry is decided (AppDelegate's onListenStart),
//  since CharacterController's shared enter() path only triggers clipKey.

final class ListenState: StateHandler {
    let name = "Listen"
    let clipKey = "listen"
    let loopsClip = true
}
