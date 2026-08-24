//
//  RunAppleScriptHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Executes NSAppleScript
//

import Foundation

/// args: `{"script": "..."}`. Approval-gated (upstream, in the agent core).
final class RunAppleScriptHandler: ToolHandler {
    let toolName = "run_applescript"

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard let script = args.extractString(key: "script") else {
            completion(.failure(.executionFailed("run_applescript requires a script string")))
            return
        }

        DispatchQueue.global().async {
            guard let appleScript = NSAppleScript(source: script) else {
                completion(.failure(.executionFailed("invalid AppleScript source")))
                return
            }

            var errorInfo: NSDictionary?
            let result = appleScript.executeAndReturnError(&errorInfo)

            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript execution failed"
                completion(.failure(.executionFailed(message)))
            } else {
                completion(.success(.string(result.stringValue ?? "")))
            }
        }
    }
}
