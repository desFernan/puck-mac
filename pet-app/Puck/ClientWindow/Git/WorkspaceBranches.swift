//
//  WorkspaceBranches.swift
//  Puck
//
//  Which branch each workspace's project is on, for the sidebar and the
//  footer.
//
//  Separate from GitStatusModel, which reads the full status of one project
//  for the git tab: this is one cheap question asked of every workspace at
//  once, and asking the expensive one per workspace would walk every worktree
//  in the sidebar every time it appeared.
//

import Foundation

@MainActor
final class WorkspaceBranches: ObservableObject {
    @Published private(set) var branches: [String: String] = [:]

    /// Reads them off the main thread; a repository on a slow disk should not
    /// hold up the sidebar it is drawn in.
    func reload(projects: [String: String]) async {
        guard !projects.isEmpty else {
            branches = [:]
            return
        }
        branches = await Task.detached(priority: .utility) {
            projects.compactMapValues { GitStatusReader.branch(projectPath: $0) }
        }.value
    }
}
