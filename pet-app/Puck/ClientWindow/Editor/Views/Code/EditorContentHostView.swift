//
//  EditorContentHostView.swift
//  Puck
//

import CodeEditSourceEditor
import SwiftUI

struct EditorContentHostView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    @ObservedObject var store: EditorPaneStore
    /// Reported upward rather than drawn here: the status line belongs under
    /// the whole code column, not inside the scroll view.
    var onCursorMoved: ((CursorPosition.Position?) -> Void)?

    @Environment(\.clientPalette) private var palette

    var body: some View {
        if let tab = store.activeTab {
            VStack(spacing: 0) {
                if tab.diskChanged {
                    ConflictBannerView(
                        onKeepMine: { store.keepMine(path: tab.path) },
                        onUseDisk: { store.useDisk(path: tab.path) }
                    )
                }
                if tab.isImage {
                    ImagePreviewView(tab: tab)
                } else {
                    CodeEditorHostView(
                        content: Binding(
                            get: { tab.content },
                            set: { store.updateDraft(path: tab.path, content: $0) }
                        ),
                        isEditable: !tab.readOnly,
                        path: tab.path,
                        reveal: store.pendingReveal,
                        find: store.pendingFind,
                        onCursorMoved: onCursorMoved
                    )
                    // Rebuilt when the file changed underneath it, not on
                    // every keystroke: see EditorTab.adoptions.
                    .id("\(tab.path)#\(tab.adoptions)")
                }
            }
            // Behind the content, so the reported rect is the code pane the
            // pet should point at rather than the whole window.
            .background(PaneFrameReporter { store.setPaneScreenFrame($0) })
        } else {
            VStack(spacing: ClientTheme.Metrics.spacingMedium) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(Strings.text(.editorSelectAFile))
                    .font(ClientTheme.Typography.sessionTitle)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
        }
    }
}
