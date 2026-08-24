//
//  AcpAgentCommand.swift
//  Puck
//
//  Port of workspace/src/shared/acp-command.ts: which executable and arguments
//  start a given coding agent. The TS version could just use Electron's own
//  bundled node (`process.execPath`); pet-app has no node of its own, so this
//  has to go looking for one.
//
//  Pure and injectable (no Process, no Bundle lookup of its own) so the search
//  order is testable without depending on what happens to be installed on the
//  machine running the tests.
//

import Foundation

enum CodingAgentKind: String, Codable, CaseIterable {
    case claude
    case codex

    /// Shown in Settings' coding-agent picker.
    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    /// The vendored bundle in Puck's resources (scripts/vendor-acp.sh).
    var bundledScriptName: String {
        switch self {
        case .claude: return "acp-claude"
        case .codex: return "acp-codex"
        }
    }

    /// The CLI the ACP shim drives. Neither shim is self-contained: each
    /// spawns its vendor's own ~256MB native binary, which this repo does not
    /// vendor -- the user's install is used instead.
    var vendorCLIName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }

    /// The variable the shim itself reads to skip its own module resolution.
    var vendorCLIEnvironmentVariable: String {
        switch self {
        case .claude: return "CLAUDE_CODE_EXECUTABLE"
        case .codex: return "CODEX_PATH"
        }
    }

    /// Where the vendor CLI keeps its own state under HOME. The child runs
    /// with the user's real HOME so it can find the login they already gave
    /// the CLI, and the seatbelt profile keeps every other path under it
    /// read-only -- this is the one directory it may also write.
    var stateDirectoryName: String {
        switch self {
        case .claude: return ".claude"
        case .codex: return ".codex"
        }
    }

    /// The environment variables the sandboxed agent reads credentials from.
    /// An explicit token still wins over the CLI's own login; Claude's
    /// setup-token is supported alongside a plain API key. Codex accepts
    /// either key name.
    var apiKeyEnvironmentVariables: [String] {
        switch self {
        case .claude: return ["CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY"]
        case .codex: return ["CODEX_API_KEY", "OPENAI_API_KEY"]
        }
    }

    var preferredCredentialEnvironmentVariable: String {
        switch self {
        case .claude: return "CLAUDE_CODE_OAUTH_TOKEN"
        case .codex: return "CODEX_API_KEY"
        }
    }
}

enum AcpAgentCommandError: Error, Equatable {
    /// No node on this machine. Only code_editor is affected; everything else
    /// in the app is unaffected, which is why this is an error value rather
    /// than something that stops the app from starting.
    case nodeNotFound
    /// The vendored .mjs is missing from the app bundle -- a packaging bug,
    /// not a user-environment one.
    case agentScriptMissing(CodingAgentKind)
    /// The agent's own vendor CLI is missing. Both ACP packages are only
    /// shims around a ~256MB per-platform native binary that this repo does
    /// not vendor (see scripts/vendor-acp.sh).
    case vendorCLINotFound(CodingAgentKind)
}

extension AcpAgentCommandError {
    /// The sentence shown when the agent could not be started at all.
    ///
    /// `purpose` names what the user was trying to do -- the same three
    /// failures read differently for a code edit and for a conversation --
    /// while the two that name a missing install stay word for word identical
    /// wherever they are reported, because the answer ("install it") does not
    /// depend on why it was wanted.
    func summary(purpose: String, kind: CodingAgentKind) -> String {
        switch self {
        case .nodeNotFound:
            return String(format: Strings.text(.acpNeedsNodeFormat), purpose)
        case .vendorCLINotFound(let missing):
            // Both agents need their vendor's own CLI installed; neither ships
            // inside Puck.app (see scripts/vendor-acp.sh).
            return String(format: Strings.text(.acpCLINotFoundFormat), missing.vendorCLIName)
        case .agentScriptMissing:
            return String(format: Strings.text(.acpAgentNotBundledFormat), kind.rawValue)
        }
    }

    /// What to say for an error that is not one of ours at all.
    static let unknownStartFailureSummary = Strings.text(.acpCouldNotStart)
}

struct AcpAgentCommand: Equatable {
    let executable: URL
    let arguments: [String]
    /// Extra environment the agent needs beyond the credentials: the path to
    /// its vendor CLI. Both shims otherwise resolve that binary out of a
    /// node_modules tree that does not exist inside Puck.app.
    let extraEnvironment: [String: String]
    /// The directory under HOME the sandbox lets this agent write, so its
    /// session state and refreshed token land where the user's own runs of
    /// the same CLI keep them. See `CodingAgentKind.stateDirectoryName`.
    let stateDirectoryName: String
}

enum AcpAgentCommandResolver {
    /// Where node usually is, in the order worth trying. PATH is consulted
    /// first (respecting the user's own choice), then the two package
    /// managers, then nvm's versioned installs -- newest first, since nvm
    /// keeps every version it has ever installed.
    static func resolveNode(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        nvmVersions: (URL) -> [String] = { directory in
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        }
    ) -> URL? {
        for directory in environment["PATH"]?.split(separator: ":") ?? [] {
            let candidate = "\(directory)/node"
            if fileExists(candidate) { return URL(fileURLWithPath: candidate) }
        }
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] where fileExists(candidate) {
            return URL(fileURLWithPath: candidate)
        }
        guard let home = environment["HOME"] else { return nil }
        let nvmRoot = URL(fileURLWithPath: home).appendingPathComponent(".nvm/versions/node")
        // Sorted descending by semver-ish string order: "v22" before "v20".
        // Not a real semver comparison -- nvm's directory names are uniform
        // enough that this picks the newest, and picking a slightly older node
        // is not a failure mode worth a version parser.
        for version in nvmVersions(nvmRoot).sorted(by: >) {
            let candidate = nvmRoot.appendingPathComponent("\(version)/bin/node").path
            if fileExists(candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }

    /// Bin directories worth looking in, and worth handing to the child, on
    /// top of whatever PATH already names. An app launched from Finder
    /// inherits launchd's PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), which names
    /// none of these -- so neither the CLI lookup here nor the child's own
    /// lookup of node/git/rg can rely on PATH alone.
    static func wellKnownBinDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        nvmVersions: (URL) -> [String] = { directory in
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        }
    ) -> [String] {
        var directories: [String] = []
        if let home = environment["HOME"] {
            directories.append("\(home)/.npm-global/bin")
            directories.append("\(home)/.local/bin")
            // Where the official Claude Code installer puts `claude`.
            directories.append("\(home)/.claude/local")
            // Same layout resolveNode searches, newest first: a node installed
            // through nvm carries the globally installed CLIs beside it.
            let nvmRoot = URL(fileURLWithPath: home).appendingPathComponent(".nvm/versions/node")
            for version in nvmVersions(nvmRoot).sorted(by: >) {
                directories.append(nvmRoot.appendingPathComponent("\(version)/bin").path)
            }
        }
        directories.append("/opt/homebrew/bin")
        directories.append("/usr/local/bin")
        return directories
    }

    /// The vendor CLI each shim actually drives -- `claude` for
    /// claude-agent-acp, `codex` for codex-acp. Honours the same override
    /// variable the shim itself reads, so a user who already set it keeps
    /// their choice.
    static func resolveVendorCLI(
        for kind: CodingAgentKind,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        nvmVersions: (URL) -> [String] = { directory in
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        }
    ) -> URL? {
        if let explicit = environment[kind.vendorCLIEnvironmentVariable], fileExists(explicit) {
            return URL(fileURLWithPath: explicit)
        }
        let name = kind.vendorCLIName
        for directory in environment["PATH"]?.split(separator: ":") ?? [] {
            let candidate = "\(directory)/\(name)"
            if fileExists(candidate) { return URL(fileURLWithPath: candidate) }
        }
        // Where the installers put it, in the order worth trying.
        let wellKnown = wellKnownBinDirectories(environment: environment, nvmVersions: nvmVersions)
        for directory in wellKnown where fileExists("\(directory)/\(name)") {
            return URL(fileURLWithPath: "\(directory)/\(name)")
        }
        return nil
    }

    static func command(
        for kind: CodingAgentKind,
        scriptURL: URL?,
        node: URL?,
        vendorCLI: URL?
    ) throws -> AcpAgentCommand {
        guard let node else { throw AcpAgentCommandError.nodeNotFound }
        guard let scriptURL else { throw AcpAgentCommandError.agentScriptMissing(kind) }
        guard let vendorCLI else { throw AcpAgentCommandError.vendorCLINotFound(kind) }
        let extraEnvironment = [kind.vendorCLIEnvironmentVariable: vendorCLI.path]
        return AcpAgentCommand(
            executable: node,
            arguments: [scriptURL.path],
            extraEnvironment: extraEnvironment,
            stateDirectoryName: kind.stateDirectoryName
        )
    }

    /// The bundled script for `kind`, or nil when the app was packaged without
    /// it. Looked up by name rather than by path: Xcode flattens a resource
    /// group into Resources/, so there is no ACP/ subdirectory to point at.
    static func bundledScriptURL(for kind: CodingAgentKind, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: kind.bundledScriptName, withExtension: "mjs")
    }
}
