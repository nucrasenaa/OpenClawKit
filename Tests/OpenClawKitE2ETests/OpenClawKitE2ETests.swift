import Foundation
import Testing
@testable import OpenClawKit

@Suite("OpenClawKit E2E")
struct OpenClawKitE2ETests {
    @Test
    func embeddedAgentRuntimeRoundTrip() async throws {
        let gateway = GatewayClient()
        try await gateway.connect(to: GatewayEndpoint(url: URL(string: "ws://127.0.0.1:18789")!))

        let runtime = EmbeddedAgentRuntime(gatewayClient: gateway)
        let result = try await runtime.run(AgentRunRequest(sessionKey: "main", prompt: "ping"))
        #expect(result.sessionKey == "main")
        #expect(result.output == "OK")

        await gateway.disconnect()
    }
}

