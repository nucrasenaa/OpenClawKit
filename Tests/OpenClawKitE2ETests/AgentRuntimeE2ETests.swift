import Foundation
import Testing
@testable import OpenClawKit

@Suite("Agent runtime E2E")
struct AgentRuntimeE2ETests {
    struct E2ETool: AgentTool {
        let name = "e2e_tool"

        func execute(arguments: [String: AnyCodable]) async throws -> AnyCodable {
            arguments["value"] ?? AnyCodable("missing")
        }
    }

    @Test
    func runIncludesToolLifecycleEvents() async throws {
        let runtime = EmbeddedAgentRuntime()
        await runtime.registerTool(E2ETool())

        let result = try await runtime.run(
            AgentRunRequest(
                runID: "e2e-1",
                sessionKey: "main",
                prompt: "run e2e",
                toolCalls: [AgentToolCall(name: "e2e_tool", arguments: ["value": AnyCodable("ok")])]
            )
        )

        #expect(result.output == "OK")
        #expect(result.toolResults.count == 1)
        #expect(result.events.map(\.kind) == [.runStarted, .toolStarted, .toolCompleted, .runCompleted])
    }
}

