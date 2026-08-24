//
//  EditorPresentation.swift
//  Puck
//
//  Where the editor pane is showing (2026-08-16). Three states rather than a
//  Bool, because "closed" and "open somewhere else" are different answers to
//  every question the chat window asks -- whether to split, how wide it has
//  to be, and what the toolbar button should say.
//
//  Detaching is cheap here because EditorPaneStorePool already keeps one store
//  per workspace alive for the process's life: the detached window and the
//  pane are two views of the same store, so open tabs, unsaved edits and the
//  file watcher survive the move in either direction.
//

import Foundation

enum EditorPresentation: Equatable {
    /// Not showing. The chat window is a chat window.
    case hidden
    /// Split beside the chat, in the same window.
    case attached
    /// In its own window. The chat window goes back to its narrow floor.
    case detached

    var isAttached: Bool { self == .attached }
    var isVisible: Bool { self != .hidden }

    /// What the toolbar's editor button does next. Detached stays detached --
    /// closing that window is how it comes back, and a button that yanked it
    /// into the split would fight the user who just moved it out.
    var toggled: EditorPresentation {
        switch self {
        case .hidden: return .attached
        case .attached: return .hidden
        case .detached: return .detached
        }
    }
}
