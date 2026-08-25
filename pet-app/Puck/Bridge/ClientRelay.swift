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
    /// What becomes of a message that arrives on the socket.
    ///
    /// Three switches used to answer parts of this question -- this one,
    /// BridgeMessageRouter's, and BridgeMessage's own Codable -- kept in
    /// step by comments. Naming the whole answer in one place means a new
    /// case has to be classified here before it compiles, and a test can
    /// walk every case and check the classification against what the router
    /// actually does with it.
    enum Disposition: Equatable {
        /// Forwarded to every connection playing this role.
        case relay(ClientRole)
        /// Answered by BridgeMessageRouter in this process.
        case handledInProcess
        /// Read before the router sees it, or sent by this process and never
        /// expected inbound. Nothing to forward and nothing to answer.
        case noReader
    }

    static func disposition(for message: BridgeMessage) -> Disposition {
        switch message {
        // user_input now goes to gui, not workspace (2026-08-15). It carries
        // what the user typed into the pet's quick-capture bubble or spoke
        // over push-to-talk, and its consumer is whoever runs the agent --
        // which was workspace's agent and is now PuckClient's.
        case .userInput, .event:
            return .relay(.gui)

        // The confirmations the in-process registry produces. Relayed to the
        // window that asked, and read by nothing here.
        case .workspaceCreate, .sessionCreate, .workspaceDelete, .voiceListening:
            return .relay(.gui)

        // Answered from the in-process WorkspaceRegistry. Relaying them as
        // well would mint a competing workspace id for one click.
        case .workspaceCreateRequest, .sessionCreateRequest, .workspaceDeleteRequest:
            return .handledInProcess

        // pet-app is the other end of each of these itself: the tool
        // exchanges, the tank the client reports, and the microphone the
        // client asks it to hold.
        case .toolDispatch, .toolCancel, .petHome, .petIslandHeight, .voiceListen:
            return .handledInProcess

        // tool_result answers a dispatch this process made; client_hello is
        // taken by BridgeServer before the router runs.
        case .toolResult, .clientHello:
            return .noReader
        }
    }

    /// - Returns: the role a message should be relayed to, or nil for
    ///   messages BridgeMessageRouter already handles locally or that are
    ///   connection-lifecycle only (client_hello).
    static func targetRole(for message: BridgeMessage) -> ClientRole? {
        guard case .relay(let role) = disposition(for: message) else { return nil }
        return role
    }
}
