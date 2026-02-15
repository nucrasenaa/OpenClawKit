import Foundation
import OpenClawCore
import OpenClawGateway
import OpenClawProtocol

public struct AgentRunRequest: Sendable {
    public let sessionKey: String
    public let prompt: String

    public init(sessionKey: String, prompt: String) {
        self.sessionKey = sessionKey
        self.prompt = prompt
    }
}

public struct AgentRunResult: Sendable {
    public let sessionKey: String
    public let output: String

    public init(sessionKey: String, output: String) {
        self.sessionKey = sessionKey
        self.output = output
    }
}

public actor EmbeddedAgentRuntime {
    private let gatewayClient: GatewayClient

    public init(gatewayClient: GatewayClient = GatewayClient()) {
        self.gatewayClient = gatewayClient
    }

    public func run(_ request: AgentRunRequest) async throws -> AgentRunResult {
        _ = try await self.gatewayClient.send(method: "agent.run", params: [
            "sessionKey": AnyCodable(request.sessionKey),
            "prompt": AnyCodable(request.prompt),
        ])
        return AgentRunResult(sessionKey: request.sessionKey, output: "OK")
    }
}

