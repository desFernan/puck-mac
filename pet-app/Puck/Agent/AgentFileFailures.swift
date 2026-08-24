//
//  AgentFileFailures.swift
//  Puck
//
//  What a file-tool failure says to the *model*, as opposed to the user.
//
//  Split from the message the editor pane shows (WorkspaceFileServiceError):
//  a person reading "file not found" in the pane already knows what
//  they clicked, while a model that guessed a path needs telling what a path
//  is supposed to look like here -- otherwise it burns a turn discovering the
//  rule by trial (observed live: show_code called with a bare "AgentRunner.swift").
//

import Foundation

extension WorkspaceFileServiceError {
    /// The failure detail handed to the model.
    var agentDetail: String {
        switch code {
        case .fileNotFound, .invalidPath, .pathOutsideWorkspace:
            return message
                + Strings.text(.toolPathIsRelativeHint)
                + Strings.text(.toolListFilesHint)
        case .fileConflict, .fileTooLarge, .binaryFile, .encodingError:
            // Nothing about the path would fix these, and a wrong suggestion
            // sends the model looking in the wrong place.
            return message
        }
    }
}

extension DispatchedToolResult {
    static func failed(_ detail: String) -> DispatchedToolResult {
        DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: detail)
    }

    static func succeeded(detail: String?) -> DispatchedToolResult {
        DispatchedToolResult(ok: true, data: nil, error: nil, detail: detail)
    }
}
