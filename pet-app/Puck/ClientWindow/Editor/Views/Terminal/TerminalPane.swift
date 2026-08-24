//
//  TerminalPane.swift
//  Puck
//
//  A shell under the editor, in the project the editor is showing.
//
//  The agent runs commands and reports what happened; this is for the times
//  that is not enough -- a build to watch, a git command to run yourself, a
//  file to look at with your own tools. It opens in the workspace's root, so
//  it starts where the conversation already is.
//
//  SwiftTerm rather than our own: a terminal is a VT emulator, a pseudo
//  terminal and a child process, and each of the three is a project.
//

import AppKit
import SwiftTerm
import SwiftUI

struct TerminalPane: NSViewRepresentable {
    /// Where the shell starts. Changing it starts a new shell -- a running
    /// one has its own idea of where it is, and moving it out from under
    /// whoever is typing would be worse than leaving it be.
    let root: String
    let palette: ClientPalette
    /// Called when the shell exits, so the pane can offer a new one rather
    /// than sitting on a dead terminal.
    let onExit: () -> Void

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        apply(palette: palette, to: view)
        view.startProcess(
            executable: Self.loginShell,
            // A login shell, so it has the PATH and the aliases the same
            // shell has in Terminal.app. Anything less and half of what is
            // typed here fails for reasons that have nothing to do with the
            // command.
            args: ["-l"],
            environment: nil,
            execName: nil,
            currentDirectory: root
        )
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        context.coordinator.onExit = onExit
        apply(palette: palette, to: view)
    }

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        // The child outlives the view otherwise: closing the pane would leave
        // a shell (and whatever it is running) attached to a terminal nobody
        // can see.
        view.terminate()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onExit: () -> Void

        init(onExit: @escaping () -> Void) {
            self.onExit = onExit
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            onExit()
        }
    }

    /// The shell the user actually uses, not whatever SwiftTerm defaults to.
    /// `SHELL` is what every terminal emulator reads for this; the fallback
    /// is macOS's own default rather than bash, which has not been the
    /// default since Catalina.
    static var loginShell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private func apply(palette: ClientPalette, to view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = NSColor(palette.background)
        view.nativeForegroundColor = NSColor(palette.textPrimary)
        // Matched to the editor beside it rather than left at the system
        // default: two monospaced views at different sizes in one column read
        // as two apps.
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }
}
