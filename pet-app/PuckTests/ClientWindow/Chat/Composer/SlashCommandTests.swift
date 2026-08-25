//
//  SlashCommandTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class SlashCommandTests: XCTestCase {
    func test_parsesEveryCommand() {
        XCTAssertEqual(SlashCommand.parse("/help"), .help)
        XCTAssertEqual(SlashCommand.parse("/fast"), .fast)
        XCTAssertEqual(SlashCommand.parse("/model"), .model(nil))
        XCTAssertEqual(SlashCommand.parse("/model gpt-5.5"), .model("gpt-5.5"))
        XCTAssertEqual(SlashCommand.parse("/effort"), .effort(nil))
        XCTAssertEqual(SlashCommand.parse("/effort high"), .effort(.high))
        XCTAssertEqual(SlashCommand.parse("/permissions"), .permissions(nil))
        XCTAssertEqual(SlashCommand.parse("/permissions all"), .permissions(.everything))
        XCTAssertEqual(SlashCommand.parse("/skills"), .skills)
    }

    /// A permission this build does not know is reported, not guessed at:
    /// picking the nearest mode would be picking how much a CLI may do to
    /// somebody's machine.
    func test_anUnknownPermissionIsRefusedRatherThanRounded() {
        XCTAssertEqual(SlashCommand.parse("/permissions everything"), .unknown("/permissions everything"))
    }

    /// Ordinary prose has to go to the agent untouched, or a message that
    /// happens to mention a path never gets sent.
    func test_leavesThingsThatAreNotCommandsAlone() {
        XCTAssertNil(SlashCommand.parse("안녕하세요"))
        XCTAssertNil(SlashCommand.parse("/usr/bin/env 를 봐줘"), "a path is not a command")
        XCTAssertNil(SlashCommand.parse("/"), "a lone slash is not a command")
        XCTAssertNil(SlashCommand.parse("/1234"))
        XCTAssertNil(SlashCommand.parse("경로는 /help 처럼 쓰세요"), "a command has to start the message")
    }

    /// A typo'd command must not become a question to the agent, which would
    /// answer it as prose.
    func test_reportsAnUnknownCommandRatherThanSendingIt() {
        XCTAssertEqual(SlashCommand.parse("/mdoel"), .unknown("/mdoel"))
        XCTAssertEqual(SlashCommand.parse("/effort yolo"), .unknown("/effort yolo"))
    }

    func test_leadingAndTrailingSpaceDoesNotHideACommand() {
        XCTAssertEqual(SlashCommand.parse("  /fast  "), .fast)
        XCTAssertEqual(SlashCommand.parse("/model   gpt-5.5  "), .model("gpt-5.5"))
    }

    func test_helpNamesEveryCommandItCanRun() {
        let help = SlashCommandRunner().run(.help)
        for name in SlashCommand.names {
            XCTAssertTrue(help.contains("/\(name)"), "/help does not mention /\(name)")
        }
    }
}

final class SlashSuggestionTests: XCTestCase {
    private func names(_ text: String) -> [String] {
        SlashCommand.suggestions(for: text).map(\.name)
    }

    /// A bare slash is someone asking what there is.
    func test_aSlashOffersEverything() {
        XCTAssertEqual(names("/"), SlashCommand.names)
    }

    func test_aPrefixNarrowsTheList() {
        XCTAssertEqual(names("/s"), ["skills"])
        XCTAssertEqual(names("/f"), ["fast"])
        XCTAssertTrue(names("/e").contains("effort"))
    }

    /// Once the name is typed and an argument is being written, a list of
    /// command names is in the way of what is actually being answered.
    func test_nothingIsOfferedOnceAnArgumentIsBeingTyped() {
        XCTAssertTrue(names("/effort ").isEmpty)
        XCTAssertTrue(names("/effort hi").isEmpty)
        XCTAssertTrue(names("/model gpt-5.5").isEmpty)
    }

    /// The same rule `parse` uses, so a message that merely mentions a path
    /// is prose in both places.
    func test_proseOffersNothing() {
        XCTAssertTrue(names("안녕하세요").isEmpty)
        XCTAssertTrue(names("/usr/bin/env 를 봐줘").isEmpty)
        XCTAssertTrue(names("경로는 /help 처럼 쓰세요").isEmpty)
    }

    func test_aNameNobodyHasOffersNothing() {
        XCTAssertTrue(names("/zzz").isEmpty)
    }

    /// Taking a suggestion has to leave something `parse` accepts, or the
    /// list would offer a command that then goes to the agent as prose.
    func test_everySuggestionCompletesToSomethingThatParses() {
        for suggestion in SlashCommand.suggestions(for: "/") {
            XCTAssertNotNil(
                SlashCommand.parse(suggestion.completion),
                "\(suggestion.completion) does not parse as a command"
            )
            XCTAssertFalse(suggestion.summary.isEmpty, "/\(suggestion.name) has no summary to show")
        }
    }
}

final class SlashCommandRunnerTests: XCTestCase {
    /// Records what a command wrote, so a test never touches the real `.env`.
    private final class Writes {
        private(set) var pairs: [(String, String?)] = []
        var succeeds = true
        func write(_ key: String, _ value: String?) -> Bool {
            pairs.append((key, value))
            return succeeds
        }
    }

    private func runner(
        _ writes: Writes,
        provider: AgentProvider = .openai,
        effort: AgentEffort = .medium,
        permissions: AgentPermissionMode = .toolsOnly,
        skills: [Skill] = []
    ) -> SlashCommandRunner {
        SlashCommandRunner(
            configuration: { AgentConfiguration.load(environment: ["AGENT_PROVIDER": provider.rawValue], searchPaths: []) },
            currentEffort: { effort },
            write: writes.write,
            currentPermissions: { permissions },
            projectPath: { "/tmp/project" },
            installedSkills: { _ in skills }
        )
    }

    func test_fastWritesTheLowestEffort() {
        let writes = Writes()
        _ = runner(writes, effort: .low).run(.fast)
        XCTAssertEqual(writes.pairs.map(\.0), [AgentEffort.environmentVariable])
        XCTAssertEqual(writes.pairs.first?.1, "low")
    }

    func test_effortWithNoArgumentWritesNothing() {
        let writes = Writes()
        let reply = runner(writes, effort: .high).run(.effort(nil))
        XCTAssertTrue(writes.pairs.isEmpty, "showing a setting must not change it")
        XCTAssertTrue(reply.contains(AgentEffort.high.displayName))
    }

    /// The CLI runs on its own configuration, so offering to set a model
    /// there would be a promise the provider cannot keep.
    func test_modelSaysTheCLIHasNoneToChoose() {
        let writes = Writes()
        let reply = runner(writes, provider: .cli).run(.model("gpt-5.5"))
        XCTAssertTrue(writes.pairs.isEmpty)
        XCTAssertTrue(reply.contains(AgentProvider.cli.displayName))
    }

    func test_modelWritesForAProviderThatHasOne() {
        let writes = Writes()
        _ = runner(writes, provider: .openai).run(.model("gpt-5.5"))
        XCTAssertEqual(writes.pairs.map(\.0), ["AGENT_MODEL"])
        XCTAssertEqual(writes.pairs.first?.1, "gpt-5.5")
    }

    /// A write that failed must say so rather than report the new value.
    func test_aFailedWriteIsReported() {
        let writes = Writes()
        writes.succeeds = false
        XCTAssertEqual(runner(writes).run(.fast), Strings.text(.slashWriteFailed))
    }

    func test_permissionsWithNoArgumentShowsTheModeWithoutChangingIt() {
        let writes = Writes()
        let reply = runner(writes, permissions: .edits).run(.permissions(nil))
        XCTAssertTrue(writes.pairs.isEmpty, "showing a setting must not change it")
        XCTAssertTrue(reply.contains(AgentPermissionMode.edits.displayName))
    }

    func test_permissionsWritesTheModeItWasGiven() {
        let writes = Writes()
        _ = runner(writes, permissions: .everything).run(.permissions(.everything))
        XCTAssertEqual(writes.pairs.map(\.0), [AgentPermissionMode.environmentVariable])
        XCTAssertEqual(writes.pairs.first?.1, AgentPermissionMode.everything.rawValue)
    }

    /// The answer is read back rather than assumed: an environment variable
    /// outranks the file this writes, and reporting a change that did not
    /// take is the confusion the whole runner exists to avoid.
    func test_permissionsReportsWhatTookEffectNotWhatWasAsked() {
        let writes = Writes()
        let reply = runner(writes, permissions: .toolsOnly).run(.permissions(.everything))
        XCTAssertTrue(
            reply.contains(AgentPermissionMode.toolsOnly.displayName),
            "the mode still in force is what gets reported"
        )
    }

    func test_skillsListsWhatIsInstalled() {
        let writes = Writes()
        let skills = [
            Skill(name: "brainstorming", description: "설계 전에 같이 생각해보기", path: "/p/.claude/skills/brainstorming/SKILL.md", source: .project),
            Skill(name: "computer-use", description: "", path: "/h/.claude/skills/computer-use/SKILL.md", source: .personal),
        ]

        let reply = runner(writes, skills: skills).run(.skills)

        XCTAssertTrue(reply.contains("brainstorming"))
        XCTAssertTrue(reply.contains("설계 전에 같이 생각해보기"))
        XCTAssertTrue(reply.contains("computer-use"), "a skill with no description is still listed")
        XCTAssertTrue(writes.pairs.isEmpty, "listing changes nothing")
    }

    /// Saying "none" is the answer; an empty list reads as a broken command.
    func test_skillsSaysSoWhenThereAreNone() {
        let reply = runner(Writes(), skills: []).run(.skills)
        XCTAssertEqual(reply, Strings.text(.slashSkillsEmpty))
    }
}

final class AgentEffortTests: XCTestCase {
    func test_unsetAndUnrecognizedResolveToTheDefault() {
        XCTAssertEqual(AgentEffort.resolved(fromRawValue: nil), .medium)
        XCTAssertEqual(AgentEffort.resolved(fromRawValue: "turbo"), .medium)
    }

    /// The default adds no instruction: telling an agent to think normally is
    /// noise, and its own tuning is what "normal" means.
    func test_onlyTheEndsCarryAnInstruction() {
        XCTAssertNil(AgentEffort.medium.promptLine)
        XCTAssertNotNil(AgentEffort.low.promptLine)
        XCTAssertNotNil(AgentEffort.high.promptLine)
    }

    func test_readsFromTheEnvironment() {
        XCTAssertEqual(AgentConfiguration.effort(environment: ["AGENT_EFFORT": "high"], searchPaths: []), .high)
        XCTAssertEqual(AgentConfiguration.effort(environment: [:], searchPaths: []), .medium)
    }
}
