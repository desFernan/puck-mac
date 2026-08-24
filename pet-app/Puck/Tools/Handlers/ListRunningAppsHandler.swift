//
//  ListRunningAppsHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Returns the list of running apps (NSWorkspace)
//

import AppKit

final class ListRunningAppsHandler: ToolHandler {
    let toolName = "list_running_apps"

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        let apps: [JSONValue] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { app in
                .object([
                    "pid": .number(Double(app.processIdentifier)),
                    "name": app.localizedName.map(JSONValue.string) ?? .null,
                    "bundle_id": app.bundleIdentifier.map(JSONValue.string) ?? .null,
                ])
            }
        completion(.success(.array(apps)))
    }
}
