//
//  UserInputSender.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Sends protocol 3.3 user_input, and tells the caller when it couldn't.
//
//  AppDelegate used to cache the last BridgeConnection handed to it by
//  BridgeServer.onMessage and never clear it, so once workspace disconnected
//  the app still believed it had a client: it wrote into a cancelled socket
//  and the input vanished with no feedback. F6 requires a "워크스페이스
//  꺼져있음" bubble in exactly that case, which needs the send to report
//  failure rather than pretend.
//

import Foundation

/// What pet-app needs from the socket layer in order to send user input.
/// Kept narrow so the decision is testable without Network.framework.
protocol UserInputTransport: AnyObject {
    /// Live state, not a remembered one — a client that disconnected must
    /// stop counting immediately.
    var hasConnectedClients: Bool { get }
    /// - Returns: whether the message actually reached >=1 live connection.
    ///   `hasConnectedClients` is only a pre-flight check; a client can
    ///   disconnect between that check and this call (BridgeConnection.onClose
    ///   races in on BridgeServer's own queue), so delivery is decided from
    ///   this return value, not the earlier snapshot.
    @discardableResult
    func broadcast(_ message: BridgeMessage) -> Bool
}

enum UserInputDelivery: Equatable {
    case sent
    /// Nothing is listening: the socket server never started, or PuckClient
    /// (which hosts the agent) is not connected. Named for the outcome rather
    /// than for who is missing -- it meant "workspace is gone" until that app
    /// was deleted on 2026-08-15, and a name that says which process is down
    /// only has to be renamed again the next time that changes.
    case notDelivered
}

final class UserInputSender {
    private let transport: () -> UserInputTransport?

    /// - Parameter transport: resolved per send, so connection state is read
    ///   fresh every time instead of captured once.
    init(transport: @escaping () -> UserInputTransport?) {
        self.transport = transport
    }

    /// - Parameters:
    ///   - workspaceId/sessionId: F13 (2026-07-29, protocol 3.4) -- default to
    ///     nil (wire default "default") for callers that don't yet know about
    ///     workspaces/sessions.
    @discardableResult
    func send(
        text: String,
        source: UserInput.Source,
        workspaceId: String? = nil,
        sessionId: String? = nil,
        attachments: [Attachment]? = nil
    ) -> UserInputDelivery {
        broadcast(.userInput(UserInput(text: text, source: source, workspaceId: workspaceId, sessionId: sessionId, attachments: attachments)))
    }

    /// F13 (2026-07-29, protocol 3.4): request a new workspace via the
    /// sidebar's "add workspace". Confirmed later by a workspace_create
    /// arriving back over the socket, which is what actually assigns
    /// workspace_id.
    @discardableResult
    func createWorkspace(name: String, projectPath: String?) -> UserInputDelivery {
        broadcast(.workspaceCreateRequest(name: name, projectPath: projectPath))
    }

    /// Reports where the pet's tank is, and whether the pet belongs in it
    /// right now (2026-08-22). Sent on every change rather than on a timer --
    /// the caller only calls this when something actually moved.
    @discardableResult
    func reportPetHome(rect: BridgeRect?, visible: Bool) -> UserInputDelivery {
        broadcast(.petHome(rect: rect, visible: visible))
    }

    /// How tall the pet stands on the island, in points, from the lever on
    /// the island itself.
    @discardableResult
    func setPetIslandHeight(_ height: Double) -> UserInputDelivery {
        broadcast(.petIslandHeight(height))
    }

    /// The chat window's mic button: pet-app owns the microphone, so this
    /// asks it to hold the push-to-talk key down (`true`) or let it up
    /// (`false`), and the transcript arrives as an ordinary voice user_input.
    @discardableResult
    func setVoiceListening(_ listening: Bool) -> UserInputDelivery {
        broadcast(.voiceListen(listening))
    }

    /// Throws a workspace away. pet-app owns the registry, so this asks and
    /// waits for the `workspace_delete` that says it happened.
    @discardableResult
    func deleteWorkspace(workspaceId: String) -> UserInputDelivery {
        broadcast(.workspaceDeleteRequest(workspaceId: workspaceId))
    }

    /// F13 (2026-07-29, protocol 3.4): request a new chat session via the
    /// sidebar's "new chat". Confirmed later by a session_create arriving
    /// back over the socket (origin: .user).
    @discardableResult
    func createSession(workspaceId: String, title: String) -> UserInputDelivery {
        broadcast(.sessionCreateRequest(workspaceId: workspaceId, title: title))
    }

    private func broadcast(_ message: BridgeMessage) -> UserInputDelivery {
        guard let transport = transport(), transport.hasConnectedClients else {
            return .notDelivered
        }
        let delivered = transport.broadcast(message)
        return delivered ? .sent : .notDelivered
    }
}
