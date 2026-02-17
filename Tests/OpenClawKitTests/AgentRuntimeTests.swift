import Foundation
import Testing
@testable import OpenClawKit

@Suite("Agent runtime")
struct AgentRuntimeTests {
    struct EchoTool: AgentTool {
        let name = "echo"

        func execute(arguments: [String: AnyCodable]) async throws -> AnyCodable {
            arguments["text"] ?? AnyCodable("")
        }
    }

    struct SlowTool: AgentTool {
        let name = "slow"

        func execute(arguments _: [String: AnyCodable]) async throws -> AnyCodable {
            try await Task.sleep(nanoseconds: 300_000_000)
            return AnyCodable("done")
        }
    }

    @Test
    func toolCallsExecuteInRunLifecycle() async throws {
        let runtime = EmbeddedAgentRuntime()
        await runtime.registerTool(EchoTool())
        let result = try await runtime.run(
            AgentRunRequest(
                runID: "run-b",
                sessionKey: "main",
                prompt: "use tool",
                toolCalls: [AgentToolCall(name: "echo", arguments: ["text": AnyCodable("hello")])]
            )
        )

        #expect(result.toolResults.count == 1)
        #expect(result.events.first?.kind == .runStarted)
        #expect(result.events.last?.kind == .runCompleted)
    }

    @Test
    func runTimesOutWhenToolIsSlow() async throws {
        let runtime = EmbeddedAgentRuntime()
        await runtime.registerTool(SlowTool())

        do {
            _ = try await runtime.run(
                AgentRunRequest(
                    runID: "run-timeout",
                    sessionKey: "main",
                    prompt: "slow",
                    toolCalls: [AgentToolCall(name: "slow")]
                ),
                timeoutMs: 50
            )
            Issue.record("Expected timeout")
        } catch {
            #expect(String(describing: error).lowercased().contains("timed"))
        }
    }

}

