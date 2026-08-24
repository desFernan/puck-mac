//
//  ClientRelay.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Which connection role a BridgeMessage should be forwarded to, now that
//  the client window is its own process (PuckClient) rather than living
//  in-process with pet-app (2026-07-30, protocol 3.7). Pure and
//  Network.framework-independent so BridgeServer's relay wiring stays
//  testable without a real socket.
//

enum ClientRelay {
    /// - Returns: the role a message should be relayed to, or nil for
    ///   messages BridgeMessageRouter already handles locally or that are
    ///   connection-lifecycle only (client_hello).
    static func targetRole(for message: BridgeMessage) -> ClientRole? {
        switch message {
        // user_input now goes to gui, not workspace (2026-08-15). It carries
        // what the user typed into the pet's quick-capture bubble or spoke
        // over push-to-talk, and its consumer is whoever runs the agent --
        // which was workspace's agent and is now PuckClient's. Left pointing
        // at workspace it would be relayed to nobody, silently breaking both
        // of those inputs.
        case .userInput, .event, .workspaceCreate, .sessionCreate, .voiceListening, .workspaceDelete:
            return .gui

        // Handled where they land rather than forwarded:
        // - workspace_create_request/session_create_request: answered from the
        //   in-process WorkspaceRegistry (BridgeMessageRouter). Relaying them
        //   as well would mint a competing workspace id for one click.
        // - tool_dispatch/tool_cancel/tool_result: pet-app is one end of each
        //   of those exchanges itself, so there is nobody to forward them to.
        // - pet_home/pet_island_height/voice_listen: pet-app is the other end
        //   of these exchanges too -- PuckClient reports or asks,
        //   BridgeMessageRouter reads them directly.
        case .workspaceCreateRequest, .sessionCreateRequest, .workspaceDeleteRequest,
             .clientHello, .toolDispatch, .toolCancel, .toolResult,
             .petHome, .petIslandHeight, .voiceListen:
            return nil
        }
    }
}
