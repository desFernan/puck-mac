//
//  EditorRevealCoordinator.swift
//  Puck
//
//  Applies EditorPaneStore.RevealRequest to the live text view: select the
//  line range, scroll it into view.
//
//  Not through SourceEditorState.cursorPositions, which is the obvious route
//  and does not work. SourceEditor only reads that binding when it first
//  makes the controller; its update path compares state.cursorPositions
//  against itself (SourceEditor.swift, 0.15.2), so nothing set afterwards
//  ever reaches the text view. A TextViewCoordinator hands over the
//  controller itself, which is the only way to set the selection at all.
//
//  Scrolling is the mirror image: the controller's own scrollToVisible does
//  not survive, because the state binding holds the previous scroll position
//  and the very next update puts it back. So the selection goes through the
//  controller and the scroll goes through the state -- each by the only route
//  that sticks.
//

import AppKit
import CodeEditSourceEditor

/// `@unchecked Sendable`: every entry point is a main-thread UI callback --
/// the editor handing over a controller it has just built or shown, or
/// SwiftUI asking for a reveal -- and the two stored properties are touched
/// nowhere else. The compiler cannot see that, because TextViewCoordinator's
/// requirements are nonisolated and so this type cannot be main-actor either.
final class EditorRevealCoordinator: TextViewCoordinator, @unchecked Sendable {
    /// Where the view should scroll to, handed back rather than done here.
    ///
    /// Scrolling the controller directly does not survive: the editor's own
    /// SwiftUI state holds the last scroll position, and the update that
    /// follows our selection change re-applies that stale value, snapping the
    /// pane straight back to where it was. Writing the position into that
    /// state instead is the one route the editor honours.
    var onScrollTarget: ((CGPoint) -> Void)?

    private weak var controller: TextViewController?
    /// Held until there is a text view to apply it to. A tour normally
    /// reveals a file that is not open yet, so the request arrives while
    /// that tab's editor is still being built.
    private var pending: ClosedRange<Int>?

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        flush()
    }

    func controllerDidAppear(controller: TextViewController) {
        self.controller = controller
        flush()
    }

    func destroy() {
        controller = nil
    }

    func reveal(lines: ClosedRange<Int>) {
        pending = lines
        flush()
    }

    /// Applies the pending reveal, if there is one and there is a text view
    /// to apply it to.
    ///
    /// `MainActor.assumeIsolated` because everything below touches the text
    /// view: TextViewController is main-actor isolated, and this type cannot
    /// be -- TextViewCoordinator's requirements are nonisolated, so a
    /// main-actor method would not satisfy them. Every route in here is the
    /// main thread already: two of the three callers are the editor telling
    /// us about a view it has just built or shown, and the third is SwiftUI.
    private func flush() {
        MainActor.assumeIsolated { flushOnMainActor() }
    }

    @MainActor
    private func flushOnMainActor() {
        guard let lines = pending, lines.lowerBound >= 1,
              let controller,
              let layoutManager = controller.textView?.layoutManager,
              // Not laid out yet: keep the request and try again from
              // controllerDidAppear.
              let first = layoutManager.textLineForIndex(lines.lowerBound - 1)
        else {
            return
        }
        pending = nil
        // A range past the end of the file selects to the last line rather
        // than nothing: the caption is still about roughly there, and a
        // silent no-op would leave the pet pointing at an unchanged screen.
        let last = layoutManager.textLineForIndex(lines.upperBound - 1) ?? first
        // An explicit NSRange rather than line/column: setCursorPositions'
        // own column arithmetic clamps a column against an absolute offset,
        // and offsets we compute here skip that entirely.
        controller.setCursorPositions([CursorPosition(range: NSRange(
            location: first.range.lowerBound,
            length: max(0, last.range.upperBound - first.range.lowerBound)
        ))])
        // A few lines of headroom, so the range reads as part of a file rather
        // than starting at its very top edge.
        onScrollTarget?(CGPoint(x: 0, y: max(0, first.yPos - first.height * 3)))
    }
}
