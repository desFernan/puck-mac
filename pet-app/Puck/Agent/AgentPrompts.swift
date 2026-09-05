//
//  AgentPrompts.swift
//  Puck
//
//  Everything AgentRunner says to the model: the system prompt, which tools
//  it is offered, and the description each one carries.
//
//  Split from the loop because they change for different reasons and on
//  different evidence. The loop changes when the protocol or the control flow
//  does; this text changes when a model misreads it, which is a tuning
//  exercise with its own rhythm -- and it was two thirds of a 900-line file
//  that is otherwise about control flow.
//

import Foundation

extension AgentRunner {
    // The members below are read by the loop in AgentRunner.swift. Swift
    // scopes `private` in an extension to its own file, so the split is
    // what widens them; `description(for:)` and the rest stay private
    // because only this file uses them.

    /// pet-app's own tools -- the ones PetToolDispatcher can actually put on
    /// the socket.
    static let petToolSpecs: [GPTToolSpec] = ToolRegistry.tools(for: .petApp).map { tool in
        GPTToolSpec(name: tool.name, description: description(for: tool.name), parameters: tool.parameters)
    }

    static let codeEditorToolName = "code_editor"
    static let openTaskSessionToolName = "open_task_session"
    static let readFileToolName = "read_file"
    static let openInEditorToolName = "open_in_editor"

    static let openTaskSessionSpec: GPTToolSpec = GPTToolSpec(
        name: openTaskSessionToolName,
        description: description(for: openTaskSessionToolName),
        parameters: ToolRegistry.tool(named: openTaskSessionToolName)?.parameters ?? []
    )

    /// The one workspace-owned tool that does have someone to run it, once a
    /// workspace is connected -- delegated rather than dispatched (see
    /// CodeEditorDelegate). Parameters come from the registry like every
    /// other tool, so the shape stays the contract's.
    static let codeEditorSpec: GPTToolSpec = {
        let tool = ToolRegistry.tool(named: codeEditorToolName)
        return GPTToolSpec(
            name: codeEditorToolName,
            description: description(for: codeEditorToolName),
            parameters: tool?.parameters ?? []
        )
    }()

    static let terminalStartToolName = "terminal_start"
    static let terminalReadToolName = "terminal_read"
    static let terminalSendToolName = "terminal_send"
    static let terminalStopToolName = "terminal_stop"

    /// The four, for the router: a name in this set goes to the terminal
    /// delegate rather than to the socket.
    static let terminalToolNames: Set<String> = [
        terminalStartToolName, terminalReadToolName, terminalSendToolName, terminalStopToolName,
    ]

    /// The four together, because they are useless apart: a start with no
    /// read is a process nobody hears from, and a read with no start has
    /// nothing to read.
    static let terminalSpecs: [GPTToolSpec] = [
        terminalStartToolName, terminalReadToolName, terminalSendToolName, terminalStopToolName,
    ].map { name in
        GPTToolSpec(
            name: name,
            description: description(for: name),
            parameters: ToolRegistry.tool(named: name)?.parameters ?? []
        )
    }

    static let readFileSpec: GPTToolSpec = GPTToolSpec(
        name: readFileToolName,
        description: description(for: readFileToolName),
        parameters: ToolRegistry.tool(named: readFileToolName)?.parameters ?? []
    )

    static let listFilesToolName = "list_files"

    static let listFilesSpec: GPTToolSpec = GPTToolSpec(
        name: listFilesToolName,
        description: description(for: listFilesToolName),
        parameters: ToolRegistry.tool(named: listFilesToolName)?.parameters ?? []
    )

    static let showCodeToolName = "show_code"

    static let showCodeSpec: GPTToolSpec = GPTToolSpec(
        name: showCodeToolName,
        description: description(for: showCodeToolName),
        parameters: ToolRegistry.tool(named: showCodeToolName)?.parameters ?? []
    )

    static let openInEditorSpec: GPTToolSpec = GPTToolSpec(
        name: openInEditorToolName,
        description: description(for: openInEditorToolName),
        parameters: ToolRegistry.tool(named: openInEditorToolName)?.parameters ?? []
    )

    private static func description(for tool: String) -> String {
        switch tool {
        case "launch_app":
            return """
            Launch a macOS app and return its pid. Pass app_name (e.g. "Weather", "Safari", \
            "System Settings") or bundle_id; bundle_id wins if both are given. Use the app's \
            English name -- that is what macOS registers even on a Korean system.
            """
        case "list_running_apps":
            return "List the apps currently running, with pid, name and bundle_id. Use this to find a pid before find_ui_element."
        case "get_frontmost_window":
            return """
            Describe the window the user is looking at: owner app, title, and frame. Returns null when             there is none. This is about a *window on screen*, not about files -- it cannot tell you             which directory or project anything is in. For that, use list_files.
            """
        case "find_ui_element":
            return """
            Query an app's Accessibility tree for one element and return its {role, title, frame, enabled}. \
            Needs the app's pid plus role or title_contains. Not finding anything is a success with null \
            data, not an error -- try a different role or title before giving up. Requires Accessibility \
            permission; without it this fails with permission_denied and you should tell the user to grant it.
            """
        case "app_snapshot":
            return """
            List what is in an app's windows: one line per element, with its role, its label and its \
            frame. Start here rather than guessing at find_ui_element -- the frames it returns are \
            exactly what point_at, click_element and scroll take, so a line from this can be used \
            directly. Needs the app's pid, from list_running_apps or launch_app. Requires \
            Accessibility permission.
            """
        case "type_text":
            return """
            Type text wherever the keyboard focus already is. This does NOT move the focus -- click \
            the field first if it is not already there. Right on any keyboard layout, so prefer it \
            over run_shell or AppleScript for putting text into an app. Requires the user's approval.
            """
        case "press_key":
            return """
            Press one key, with modifiers: "Return", "escape", "tab", "cmd+s", "cmd+shift+p". For \
            keys that have no character -- to type characters use type_text. Requires the user's \
            approval.
            """
        case "scroll":
            return """
            Scroll up or down, at the pointer or at the centre of `frame` if you pass one. `lines` \
            defaults to a small nudge; call it again rather than asking for a huge number. Use this \
            to read a window that does not fit on screen, then app_snapshot again to see what came \
            into view.
            """
        case "point_at":
            return """
            Walk the pet to a point on screen and have it point at it. Takes frame \
            {x, y, width, height} in Quartz global screen coordinates (top-left origin, Y down) -- \
            exactly what find_ui_element returns, so pass that through unchanged. This is how you \
            SHOW the user where something is instead of clicking it for them.
            """
        case "click_element":
            return """
            Synthesize a real mouse click at the centre of frame. Requires the user's approval. \
            This does NOT work on macOS system permission or security dialogs -- for those it fails \
            with not_supported_target, and you must fall back to point_at and ask the user to click \
            it themselves.
            """
        case "run_shell":
            return "Run a shell command via /bin/zsh and return stdout, stderr and the exit code. Requires the user's approval."
        case "run_applescript":
            return "Run an AppleScript and return its result as a string. Requires the user's approval. Use this for app automation that has no dedicated tool."
        case openTaskSessionToolName:
            return """
            Move this conversation into a new task session before starting real work. Whenever the \
            user asks for code to be written or changed, call this first and wait for its result; \
            call code_editor on the next turn. `title` is a short label for the sidebar in the user's language \
            (e.g. "hello.ts 주석 추가"); `brief` is one line on what the task is. Everything you say \
            after this lands in the new session, so the casual chat stays readable and the user can \
            stop the coding work without stopping the conversation. Do not call it for questions, \
            explanations, or anything you answer without editing files.
            """
        case codeEditorToolName:
            return """
            Hand a coding task to the workspace editor's own coding agent, which reads and edits the \
            files of the project the user has open and reports back what it changed. Pass `task` as \
            one self-contained instruction in the user's own words -- the editor agent cannot see \
            this conversation, so include everything it needs (which file or feature, what to change, \
            any constraint the user gave). Do NOT pass project_path; the workspace decides that. \
            This is the only way to change files: never use run_shell to edit code. It can take \
            minutes, and the user watches the edit happen in the editor while it runs. Returns the \
            editor agent's summary, or fails with pet_app_disconnected when the pet app is not \
            running -- in which case tell the user to start Puck.
            """
        case readFileToolName:
            return """
            Return a file's contents from the project the current workspace has open, read-only. \
            `path` is relative to the project root (or absolute, as long as it's inside the project). \
            Use this to answer questions about code or show the user what a file contains -- it does \
            not open a tab in the editor pane; use open_in_editor for that. Fails with execution_failed \
            if the workspace has no project open, the path doesn't exist, or the file is binary/too large.
            """
        case listFilesToolName:
            return """
            List the project's files as relative paths. Pass `contains` to narrow it to paths holding \
            that text (case-insensitive, matched against the whole path): "bubble", "Pointing/", \
            ".swift". Use it to find the file you need before read_file or show_code, instead of \
            guessing a path -- a large project returns only its first 400 paths without a filter, \
            and those may all be generated output. Never use run_shell to look for files.
            """
        case terminalStartToolName:
            return """
            Start a command that keeps running -- a dev server, a test watcher, a build -- in the \
            project's directory, and return its terminal id. It returns as soon as the command has \
            started, NOT when it finishes: that is the whole point. Use run_shell instead for \
            anything that ends on its own within a minute. Read what it says with terminal_read a \
            few seconds later, so you can tell the user whether it actually came up.
            """
        case terminalReadToolName:
            return """
            Everything a terminal has said since you last read it -- new output only, so reading \
            twice does not repeat itself. Also says whether it is still running, and its exit code \
            if it stopped. An empty read means it has said nothing new, which for a server that is \
            already up is the normal answer, not a failure.
            """
        case terminalSendToolName:
            return """
            Type one line into a running terminal, as though at its prompt -- for answering \
            something that is waiting on input. The newline is added for you. Requires the user's \
            approval.
            """
        case terminalStopToolName:
            return """
            End a terminal you started. Pass `id` for one, or leave it out to stop all of them. Its \
            output stays readable afterwards, which is usually the part worth looking at. Stop what \
            you started once you are done: these are real processes on the user's machine.
            """
        case openInEditorToolName:
            return """
            Open a file as a tab in the client window's editor pane, so the user can see (and, if they \
            choose, edit) it themselves. `path` is relative to the project root. This does not return \
            the file's contents to you -- call read_file first if you need to know what's in it. Use \
            this when the user asks to see or work on a specific file, not as a way to read it yourself.
            """
        case showCodeToolName:
            return """
            Show the user a specific range of lines: the editor highlights them and the pet walks \
            over and points at the pane while saying `caption`. Call it once per stop of a \
            walkthrough, in reading order, and explain that stop in your reply right after. \
            `path` is relative to the project root and `start_line`/`end_line` are 1-indexed. \
            `caption` is ONE short line in the user's language for the pet to say out loud -- the \
            real explanation goes in your reply, not in the caption. It returns only once the pet \
            has arrived, so call the next stop only after this one answers.
            """
        default:
            return tool
        }
    }

    static let systemPrompt = """
    You are the brain of Puck, a desktop pet that carries out the user's requests on their Mac. \
    A 3D pet lives on the screen and physically acts out what you do: it walks to windows, points at \
    things, and reacts to every tool you call. The user sees the pet, not you.

    Rules:
    - Answer in the user's language. Korean input gets Korean answers.
    - Be brief. Say what you did, not how you decided to do it. One or two sentences.
    - Prefer showing over doing: when the user asks where something is, use find_ui_element and then \
      point_at so the pet guides them, rather than clicking it yourself.
    - click_element, run_shell and run_applescript need the user's approval, which costs them an \
      interruption -- reach for them only when no gentler tool does the job.
    - click_element never works on system permission dialogs. When one is involved, point_at it and \
      tell the user to click it themselves.
    - Call tools through the tool interface, one at a time. NEVER write a tool call as text or as \
      a code snippet -- code in your reply is something the user reads, not something that runs. If \
      no tool can do what was asked, say so plainly instead of writing what the call would look like.
    - A command that does not finish on its own -- a dev server, a watcher, a build you want to \
      follow -- goes to terminal_start, not run_shell. run_shell waits for an exit that never \
      comes and kills it at its timeout. Read it back with terminal_read a few seconds later \
      rather than immediately: a server that has not printed its port yet has not failed.
    - When the user asks for code to be written or changed, use code_editor if you have it. You \
      never edit files yourself, and the shell is not a substitute for it. If you also have \
      open_task_session, call it first so the editing runs in its own session.
    - If you have read_file, use it (not run_shell/cat) to read or show a file's contents -- it's \
      read-only and costs no approval. Use open_in_editor, if you have it, when the user should see \
      or edit the file themselves instead of just being told what's in it. Neither edits a file; \
      code_editor is the only tool that changes one.
    - If you have show_code, use it when the user asks you to explain, review or walk through \
      code: one call per place worth looking at, then your explanation of that place. Reading a \
      file to answer a plain question does not need it.
    - When a tool fails with permission_denied, tell the user which permission to grant in System \
      Settings. When it fails with pet_app_disconnected, tell them the pet app isn't running.
    - Never claim you did something a tool did not actually report success for.
    """
}
