//
//  MCPToolCatalogTests.swift
//  PuckTests
//
//  The tool list handed to the CLI is derived, not written down a second time.
//  These pin the derivation, including the one deliberate exclusion.
//

import XCTest
@testable import Puck

final class MCPToolCatalogTests: XCTestCase {

    func test_inputSchema_namesEveryParameterAndOnlyRequiresTheRequiredOnes() {
        let schema = MCPToolCatalog.inputSchema(for: [
            ToolRegistry.Parameter(name: "pid", type: .number, isRequired: true),
            ToolRegistry.Parameter(name: "role", type: .string, isRequired: false),
        ])

        XCTAssertEqual(schema["type"]?.stringValue, "object")
        XCTAssertEqual(schema["properties"]?["pid"]?["type"]?.stringValue, "number")
        XCTAssertEqual(schema["properties"]?["role"]?["type"]?.stringValue, "string")
        XCTAssertEqual(schema["required"]?.arrayValue, [.string("pid")])
    }

    /// An empty `required` reads to some validators as a constraint rather
    /// than the absence of one, and a no-parameter tool has none.
    func test_inputSchema_omitsRequiredEntirelyWhenNothingIs() {
        let schema = MCPToolCatalog.inputSchema(for: [])

        XCTAssertNil(schema["required"])
        XCTAssertEqual(schema["properties"], .object([:]))
    }

    func test_definitions_carryTheDescriptionTheModelIsGivenElsewhere() {
        let definitions = MCPToolCatalog.definitions(for: [
            GPTToolSpec(name: "point_at", description: "Walk the pet to a point.", parameters: []),
        ])

        XCTAssertEqual(definitions.count, 1)
        XCTAssertEqual(definitions.first?["name"]?.stringValue, "point_at")
        XCTAssertEqual(definitions.first?["description"]?.stringValue, "Walk the pet to a point.")
    }

    /// Both exclusions are handoffs to a coding agent that isn't there on this
    /// provider -- open_task_session's own description tells the model to call
    /// code_editor next. Everything else must survive, so a tool added to the
    /// registry reaches the CLI without anyone remembering to list it here.
    func test_definitions_dropTheCodingHandoffsAndNothingElse() {
        let specs = ToolRegistry.all.map {
            GPTToolSpec(name: $0.name, description: $0.name, parameters: $0.parameters)
        }

        let names = MCPToolCatalog.definitions(for: specs).compactMap { $0["name"]?.stringValue }

        XCTAssertFalse(names.contains("code_editor"))
        XCTAssertFalse(names.contains("open_task_session"))
        XCTAssertEqual(names.count, ToolRegistry.all.count - MCPToolCatalog.excludedToolNames.count)
        for tool in ToolRegistry.all where !MCPToolCatalog.excludedToolNames.contains(tool.name) {
            XCTAssertTrue(names.contains(tool.name), "\(tool.name) must be reachable from the CLI")
        }
    }
}
