//
//  AgentConfigurationTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Reading the key out of a .env, and the precedence between the places one
//  can live -- getting this wrong looks like "the key I just set is being
//  ignored", which is a miserable thing to debug.
//

import XCTest
@testable import Puck

final class DotEnvTests: XCTestCase {
    func test_readsPlainAssignments() {
        let parsed = DotEnv.parse("OPENAI_API_KEY=sk-abc\nOPENAI_MODEL=gpt-4o")

        XCTAssertEqual(parsed["OPENAI_API_KEY"], "sk-abc")
        XCTAssertEqual(parsed["OPENAI_MODEL"], "gpt-4o")
    }

    func test_ignoresCommentsAndBlankLines() {
        let parsed = DotEnv.parse("""
        # the agent's key

        OPENAI_API_KEY=sk-abc
        """)

        XCTAssertEqual(parsed, ["OPENAI_API_KEY": "sk-abc"])
    }

    func test_acceptsExportPrefixAndQuotes() {
        let parsed = DotEnv.parse("""
        export OPENAI_API_KEY="sk-abc"
        OPENAI_MODEL='gpt-4o'
        """)

        XCTAssertEqual(parsed["OPENAI_API_KEY"], "sk-abc")
        XCTAssertEqual(parsed["OPENAI_MODEL"], "gpt-4o")
    }

    /// Keys contain '='. Splitting on every one of them silently truncates the
    /// key, which then fails as a 401 rather than as a parse error.
    func test_splitsOnTheFirstEqualsOnly() {
        let parsed = DotEnv.parse("OPENAI_API_KEY=sk-abc==tail")

        XCTAssertEqual(parsed["OPENAI_API_KEY"], "sk-abc==tail")
    }

    func test_missingFileIsEmptyRatherThanAFailure() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)/.env")

        XCTAssertTrue(DotEnv.parse(fileAt: missing).isEmpty)
    }
}

final class AgentConfigurationTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        directories = []
        super.tearDown()
    }

    /// A temp directory holding a .env with `contents`.
    private func directory(withEnv contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        try contents.write(to: url.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        return url
    }

    func test_readsTheKeyAndModelFromADotEnv() throws {
        let directory = try directory(withEnv: "AGENT_PROVIDER=openai\nOPENAI_API_KEY=sk-from-file\nOPENAI_MODEL=gpt-4.1")

        let configuration = AgentConfiguration.load(environment: [:], searchPaths: [directory])

        XCTAssertTrue(configuration.isConfigured)
        XCTAssertEqual(configuration.apiKey, "sk-from-file")
        XCTAssertEqual(configuration.model, "gpt-4.1")
    }

    /// A hand-written `.env` is typed by a person, and every other setting
    /// here folds case. `AGENT_PROVIDER=OpenAI` used to fall through to the
    /// fallback, so the app talked to a coding CLI while the person who wrote
    /// that line believed they had chosen OpenAI.
    func test_theProviderIsReadWhateverCaseItIsWrittenIn() throws {
        for spelling in ["openai", "OpenAI", "OPENAI"] {
            let directory = try directory(withEnv: "AGENT_PROVIDER=\(spelling)\nOPENAI_API_KEY=sk-x")

            let configuration = AgentConfiguration.load(environment: [:], searchPaths: [directory])

            XCTAssertEqual(configuration.provider, .openai, "\(spelling) should name the same provider")
        }
    }

    func test_environmentBeatsTheFile_soAOneOffOverrideNeedsNoEdit() throws {
        let directory = try directory(withEnv: "AGENT_PROVIDER=openai\nOPENAI_API_KEY=sk-from-file")

        let configuration = AgentConfiguration.load(
            environment: ["OPENAI_API_KEY": "sk-from-environment"],
            searchPaths: [directory]
        )

        XCTAssertEqual(configuration.apiKey, "sk-from-environment")
    }

    /// Nearest-first: the first .env that supplies a value owns it, so adding
    /// a fallback file can never shadow the one next to the project.
    func test_theEarlierSearchPathWins() throws {
        let nearer = try directory(withEnv: "AGENT_PROVIDER=openai\nOPENAI_API_KEY=sk-nearer")
        let further = try directory(withEnv: "OPENAI_API_KEY=sk-further\nOPENAI_MODEL=gpt-4.1")

        let configuration = AgentConfiguration.load(environment: [:], searchPaths: [nearer, further])

        XCTAssertEqual(configuration.apiKey, "sk-nearer")
        // …but a value only the further file has still comes through.
        XCTAssertEqual(configuration.model, "gpt-4.1")
    }

    /// The `#filePath` walk has to land on the repo root, or `pet-app/.env`
    /// -- the whole point of that search path -- is looked for in the wrong
    /// directory and silently never found.
    func test_repositoryDirectoryIsTheRepoRoot() throws {
        let repository = try XCTUnwrap(AgentConfiguration.repositoryDirectory, "Debug builds must resolve a repo directory")

        XCTAssertEqual(repository.lastPathComponent, "pet-app")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: repository.appendingPathComponent("project.yml").path),
            "expected the repo root to contain project.yml, got \(repository.path)"
        )
        XCTAssertTrue(
            AgentConfiguration.defaultSearchPaths.contains(repository),
            ".env next to project.yml has to actually be searched"
        )
    }

    func test_noKeyAnywhere_isNotConfiguredAndStillHasADefaultModel() {
        let configuration = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "openai"], searchPaths: [])

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertEqual(configuration.model, AgentConfiguration.defaultModel)
    }

    /// The OpenAI default shipped as gpt-5.3-codex, which v1/chat/completions
    /// -- the only endpoint GPTClient posts to -- refuses with a 404 saying to
    /// use v1/responses instead. Every fresh install with a perfectly good key
    /// therefore got "모델을 찾을 수 없어요" on its first turn.
    ///
    /// A unit test cannot ask OpenAI what it serves, and `/v1/models` is no
    /// help: it lists codex models regardless of which endpoint accepts them.
    /// What it can do is hold the line that made the default unusable -- no
    /// Responses-API-only family in a chat/completions default. Switching
    /// GPTClient to v1/responses is what would retire this test.
    func test_openAIDefaultModel_isOneChatCompletionsCanServe() {
        XCTAssertFalse(
            AgentConfiguration.defaultModel.contains("codex"),
            "codex models are Responses-API only; GPTClient posts to v1/chat/completions"
        )
    }

    /// An empty assignment is the same as not setting it -- otherwise an
    /// `OPENAI_API_KEY=` left in a file reports "configured" and fails at the
    /// API instead of at startup.
    func test_blankValuesCountAsAbsent() throws {
        let directory = try directory(withEnv: "AGENT_PROVIDER=openai\nOPENAI_API_KEY=\nOPENAI_MODEL=   ")

        let configuration = AgentConfiguration.load(environment: [:], searchPaths: [directory])

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertEqual(configuration.model, AgentConfiguration.defaultModel)
    }

    // MARK: - Provider

    func test_defaultsToTheCLIWhenNothingSelectsAProvider() {
        let config = AgentConfiguration.load(environment: [:], searchPaths: [])
        XCTAssertEqual(config.provider, .cli)
        // Pairs with codingAgent()'s own default, so the pair a fresh install
        // gets is the coding agent this repo vendors.
        XCTAssertEqual(config.codingAgent, .claude)
    }

    func test_readsProviderFromEnvironment() {
        let config = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "anthropic"], searchPaths: [])
        XCTAssertEqual(config.provider, .anthropic)
    }

    func test_unknownProviderFallsBackToTheDefault() {
        let config = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "gemini"], searchPaths: [])
        XCTAssertEqual(config.provider, AgentProvider.fallback)
    }

    func test_selectedProviderDecidesWhichKeyIsRead() {
        let env = ["AGENT_PROVIDER": "anthropic", "ANTHROPIC_API_KEY": "sk-ant-x", "OPENAI_API_KEY": "sk-oai-y"]
        XCTAssertEqual(AgentConfiguration.load(environment: env, searchPaths: []).apiKey, "sk-ant-x")

        var openAIEnv = env
        openAIEnv["AGENT_PROVIDER"] = "openai"
        XCTAssertEqual(AgentConfiguration.load(environment: openAIEnv, searchPaths: []).apiKey, "sk-oai-y")
    }

    func test_eachProviderHasItsOwnDefaultModel() {
        let openAI = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "openai"], searchPaths: [])
        let anthropic = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "anthropic"], searchPaths: [])
        XCTAssertNotEqual(openAI.model, anthropic.model)
        XCTAssertFalse(anthropic.model.isEmpty)
    }

    /// `AGENT_MODEL` is a provider-neutral override, but a legacy
    /// `OPENAI_MODEL` must keep winning for OpenAI users -- adding the
    /// neutral variable can't silently change behavior for anyone who
    /// already relies on the specific one.
    func test_legacyOpenAIModelVariableStillWinsOverProviderNeutralOne() {
        let config = AgentConfiguration.load(
            environment: ["AGENT_PROVIDER": "openai", "OPENAI_MODEL": "gpt-4.1", "AGENT_MODEL": "gpt-5"],
            searchPaths: []
        )

        XCTAssertEqual(config.model, "gpt-4.1")
    }

    /// With no provider-specific override, the neutral variable still works
    /// -- it exists precisely so a provider switch doesn't also require
    /// renaming the model override.
    func test_agentModelIsUsedWhenNoProviderSpecificOverrideIsSet() {
        let config = AgentConfiguration.load(
            environment: ["AGENT_PROVIDER": "anthropic", "AGENT_MODEL": "claude-opus-5"],
            searchPaths: []
        )

        XCTAssertEqual(config.model, "claude-opus-5")
    }

    // MARK: - The CLI provider

    func test_readsTheCliProviderFromEnvironment() {
        let config = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "cli"], searchPaths: [])

        XCTAssertEqual(config.provider, .cli)
    }

    /// The point of offering a CLI as a provider is that the user already
    /// logged into it. Holding no token of our own is the ordinary case, not
    /// a misconfiguration, so a turn still starts -- and if the CLI's own
    /// login is missing the CLI is the one that says so.
    func test_theCliProviderIsConfiguredWithoutAKeyOfOurs() {
        let config = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "cli"], searchPaths: [])

        XCTAssertTrue(config.isConfigured)
        XCTAssertNil(config.apiKey)
        XCTAssertNil(config.keySource)
        XCTAssertNil(config.provider.apiKeyEnvironmentVariable)
        XCTAssertFalse(config.provider.requiresAPIKey)
        XCTAssertFalse(config.requiresCredential)
        // ...but Settings still offers the field, since an explicit token
        // overrides whatever login the CLI would have used.
        XCTAssertTrue(config.acceptsCredential)
    }

    /// A key sitting in the same .env for another provider must not be picked
    /// up and reported as this one's source -- Settings' status line would
    /// then name a file that has nothing to do with the selected provider.
    func test_theCliProviderIgnoresKeysMeantForTheOthers() throws {
        let directory = try directory(withEnv: "AGENT_PROVIDER=cli\nGOOGLE_API_KEY=unrelated")

        let config = AgentConfiguration.load(environment: [:], searchPaths: [directory])

        XCTAssertEqual(config.provider, .cli)
        XCTAssertNil(config.apiKey)
        XCTAssertNil(config.keySource)
    }

    func test_theCliProviderLoadsTheSelectedAgentsStableCredential() {
        let config = AgentConfiguration.load(
            environment: [
                "AGENT_PROVIDER": "cli",
                "CODING_AGENT": "codex",
                "OPENAI_API_KEY": "codex-key",
            ],
            searchPaths: []
        )

        XCTAssertEqual(config.codingAgent, .codex)
        XCTAssertEqual(config.apiKey, "codex-key")
        XCTAssertEqual(config.keySource, .environment(variable: "OPENAI_API_KEY"))
        XCTAssertTrue(config.isConfigured)
    }

    func test_cliEnvironmentCredentialBeatsAFileCredential() throws {
        let directory = try directory(withEnv: "AGENT_PROVIDER=cli\nANTHROPIC_API_KEY=file-key")

        let config = AgentConfiguration.load(
            environment: [
                "AGENT_PROVIDER": "cli",
                "CLAUDE_CODE_OAUTH_TOKEN": "environment-token",
            ],
            searchPaths: [directory]
        )

        XCTAssertEqual(config.apiKey, "environment-token")
        XCTAssertEqual(config.keySource, .environment(variable: "CLAUDE_CODE_OAUTH_TOKEN"))
    }

    func test_claudeSetupTokenIsForwardedWithoutInteractiveLoginState() {
        let config = AgentConfiguration.load(environment: ["AGENT_PROVIDER": "cli"], searchPaths: [])

        let credentials = config.codingAgentCredentials(
            for: .claude,
            environment: [
                "CLAUDE_CODE_OAUTH_TOKEN": "setup-token",
                "CLAUDE_CODE_OAUTH_REFRESH_TOKEN": "short-lived-refresh",
            ],
            searchPaths: []
        )

        XCTAssertEqual(credentials, ["CLAUDE_CODE_OAUTH_TOKEN": "setup-token"])
    }

    /// ACP carries no model field, so nothing would send one. Resolving
    /// AGENT_MODEL here anyway would put a model name in Settings that no
    /// request ever mentions.
    func test_theCliProviderResolvesNoModel() {
        let config = AgentConfiguration.load(
            environment: ["AGENT_PROVIDER": "cli", "AGENT_MODEL": "gpt-5", "OPENAI_MODEL": "gpt-4.1"],
            searchPaths: []
        )

        XCTAssertEqual(config.model, "")
        XCTAssertFalse(config.provider.supportsModelSelection)
        XCTAssertNil(config.provider.modelEnvironmentVariable)
    }

    /// What Settings writes has to be what `load` reads back, through the
    /// real file rather than a hand-built dictionary: the picker and the
    /// loader are in two different processes and the `.env` is the only thing
    /// between them.
    func test_writingProviderAndCodingAgentToADotEnvRoundTrips() throws {
        let directory = try directory(withEnv: "# puck\n")
        let file = directory.appendingPathComponent(".env")

        XCTAssertTrue(DotEnv.write(key: "AGENT_PROVIDER", value: "cli", to: file))
        XCTAssertTrue(DotEnv.write(key: "CODING_AGENT", value: "codex", to: file))

        XCTAssertEqual(AgentConfiguration.load(environment: [:], searchPaths: [directory]).provider, .cli)
        XCTAssertEqual(AgentConfiguration.codingAgent(environment: [:], searchPaths: [directory]), .codex)

        // And switching back, which is a rewrite of an existing assignment
        // rather than an append -- the case that eats a line when it's wrong.
        XCTAssertTrue(DotEnv.write(key: "AGENT_PROVIDER", value: "anthropic", to: file))
        XCTAssertEqual(AgentConfiguration.load(environment: [:], searchPaths: [directory]).provider, .anthropic)
        XCTAssertEqual(AgentConfiguration.codingAgent(environment: [:], searchPaths: [directory]), .codex)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("# puck"))
    }

    /// The model field Settings now offers writes the provider-specific
    /// variable, and clearing it falls back to the provider's default.
    func test_writingAModelToADotEnvRoundTripsAndClears() throws {
        let directory = try directory(withEnv: "AGENT_PROVIDER=openai\n")
        let file = directory.appendingPathComponent(".env")

        XCTAssertTrue(DotEnv.write(key: "OPENAI_MODEL", value: "gpt-4.1", to: file))
        XCTAssertEqual(AgentConfiguration.load(environment: [:], searchPaths: [directory]).model, "gpt-4.1")

        XCTAssertTrue(DotEnv.write(key: "OPENAI_MODEL", value: nil, to: file))
        XCTAssertEqual(
            AgentConfiguration.load(environment: [:], searchPaths: [directory]).model,
            AgentConfiguration.defaultModel
        )
    }
}

/// F15 (task 4, revised task 8): `makeAgentLLMClient` is the single place
/// `AgentHost`'s construction site (PuckClient/AgentHost.swift) builds the
/// client `AgentRunner` gets -- getting this wrong means every request goes
/// to the wrong host regardless of which key Settings has stored.
///
/// It now always returns a `RoutingAgentLLMClient` (task 8's gap-2 fix)
/// rather than a `GPTClient`/`ClaudeClient` chosen once at construction, so
/// a provider switch in Settings takes effect on the next `send` instead of
/// the next relaunch. `RoutingAgentLLMClientTests` covers that per-request
/// routing behavior directly (with spy clients); these two cases just
/// confirm the factory always hands back a router, for every provider and
/// for the no-`AGENT_PROVIDER` default alike.
final class MakeAgentLLMClientTests: XCTestCase {
    func test_factoryReturnsARouter_forEitherExplicitProvider() {
        let openAI = makeAgentLLMClient({ AgentConfiguration.load(environment: ["AGENT_PROVIDER": "openai"], searchPaths: []) })
        XCTAssertTrue(openAI is RoutingAgentLLMClient)

        let anthropic = makeAgentLLMClient({ AgentConfiguration.load(environment: ["AGENT_PROVIDER": "anthropic"], searchPaths: []) })
        XCTAssertTrue(anthropic is RoutingAgentLLMClient)

        // Including the one that spawns a process rather than making an HTTP
        // request -- constructing it must still spawn nothing.
        let cli = makeAgentLLMClient({ AgentConfiguration.load(environment: ["AGENT_PROVIDER": "cli"], searchPaths: []) })
        XCTAssertTrue(cli is RoutingAgentLLMClient)
    }

    /// No `AGENT_PROVIDER` at all resolves to `.cli` (AgentConfiguration's
    /// own default) -- the factory has to follow that fallback rather than
    /// crash or pick arbitrarily. `RoutingAgentLLMClient` re-reads this on
    /// every `send`, so the default only has to be right in `configuration`,
    /// not baked into which class got picked.
    func test_factoryReturnsARouter_whenNoProviderIsSet() {
        let client = makeAgentLLMClient({ AgentConfiguration.load(environment: [:], searchPaths: []) })
        XCTAssertTrue(client is RoutingAgentLLMClient)
    }
}
