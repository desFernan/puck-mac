//
//  ToolTimeouts.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Each tool's `timeout_sec`. This began as a mirror of the protocol repo's
//  own table; that repo was folded away in the native rewrite, so this file
//  is the registry now rather than a copy of one.
//
//  Only the timeouts are mirrored, not the whole registry: `timeout_sec` is
//  the one registry field a tool_dispatch *receiver* needs but the wire does
//  not carry (the sender owns the real timeout, the
//  receiver only needs a bound that is not tighter than the registry's).
//  Executor/approval/params stay TS-only because no Swift-side consumer
//  reads them.
//

import Foundation

enum ToolTimeouts {
    /// Applied to any tool absent from `bySeconds` -- an unknown tool is
    /// rejected before dispatch anyway, so this only covers a registry entry
    /// that shipped in TS before this mirror caught up.
    static let defaultSeconds: TimeInterval = 15

    /// tool name -> `timeoutSec` from src/types/tools.ts.
    static let bySeconds: [String: TimeInterval] = [
        // pet-app executor
        "launch_app": 15,
        "list_running_apps": 5,
        "get_frontmost_window": 5,
        "find_ui_element": 15,
        "point_at": 30,
        "click_element": 15,
        // Walking a whole app's tree is find_ui_element's work and then some,
        // so it gets the same bound the inspector already runs under.
        "app_snapshot": 15,
        // Typing is paced, so a long string genuinely takes a moment.
        "type_text": 30,
        "press_key": 5,
        "scroll": 5,
        "run_shell": 60,
        "run_applescript": 60,
        // workspace executor. 600 is now how long the agent may stay *silent*
        // rather than how long a run may take -- CodeEditorRunner puts the
        // clock back on every ACP update (see AgentProgress), so a long edit
        // is no longer a timeout.
        "code_editor": 600,
        // The agent's own shells (2026-09-04). None of the four waits for the
        // command itself -- a start answers when the process has launched and
        // a read answers with whatever is buffered -- so these bound the call,
        // not the work. See AgentTerminals.
        "terminal_start": 15,
        "terminal_read": 10,
        "terminal_send": 10,
        "terminal_stop": 10,
        "open_in_editor": 10,
        "list_files": 15,
        "read_file": 10,
        // A stop is a point_at (30) plus the walk to the pane and the wait
        // for it to report where it is, so it cannot be tighter than that.
        "show_code": 45,
        // ai-module executor -- never dispatched, so this never actually
        // applies; 0 mirrors tools.ts's placeholder value (2026-07-29).
        "open_task_session": 0,
    ]

    /// The registry timeout for `tool`, or `defaultSeconds` if unlisted.
    static func seconds(for tool: String) -> TimeInterval {
        bySeconds[tool] ?? defaultSeconds
    }
}
