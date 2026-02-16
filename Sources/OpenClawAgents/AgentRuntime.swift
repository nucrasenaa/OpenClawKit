import Foundation
import OpenClawCore
import OpenClawGateway
import OpenClawModels
import OpenClawProtocol

public enum AgentRuntimeError: Error, LocalizedError, Sendable {
    case toolNotFound(String)
    case timedOut(runID: String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .timedOut(let runID):
            return "Agent run timed out: \(runID)"
        }
    }
}

public struct AgentRunEvent: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case runStarted
        case toolStarted
        case toolCompleted
        case runCompleted
    }

    public let runID: String
    public let kind: Kind
    public let toolName: String?

    public init(runID: String, kind: Kind, toolName: String? = nil) {
        self.runID = runID
        self.kind = kind
        self.toolName = toolName
    }
}

public struct AgentRunRequest: Sendable {
    public let runID: String
    public let sessionKey: String
    public let prompt: String
    public let toolCalls: [AgentToolCall]
    public let modelProviderID: String?

    public init(
        runID: String = UUID().uuidString,
        sessionKey: String,
        prompt: String,
        toolCalls: [AgentToolCall] = [],
        modelProviderID: String? = nil
    ) {
        self.runID = runID
        self.sessionKey = sessionKey
        self.prompt = prompt
        self.toolCalls = toolCalls
        self.modelProviderID = modelProviderID
    }
}

public struct AgentRunResult: Sendable {
    public let runID: String
    public let sessionKey: String
    public let output: String
    public let toolResults: [AgentToolResult]
    public let events: [AgentRunEvent]

    public init(
        runID: String,
        sessionKey: String,
        output: String,
        toolResults: [AgentToolResult],
        events: [AgentRunEvent]
    ) {
        self.runID = runID
        self.sessionKey = sessionKey
        self.output = output
        self.toolResults = toolResults
        self.events = events
    }
}

public actor EmbeddedAgentRuntime {
    private let gatewayClient: GatewayClient
    private let toolRegistry: AgentToolRegistry
    private let modelRouter: ModelRouter

    public init(
        gatewayClient: GatewayClient = GatewayClient(),
        toolRegistry: AgentToolRegistry = AgentToolRegistry(),
        modelRouter: ModelRouter = ModelRouter()
    ) {
        self.gatewayClient = gatewayClient
        self.toolRegistry = toolRegistry
        self.modelRouter = modelRouter
    }

    public func registerTool(_ tool: any AgentTool) async {
        await self.toolRegistry.register(tool)
    }

    public func registerModelProvider(_ provider: any ModelProvider) async {
        await self.modelRouter.register(provider)
    }

    public func setDefaultModelProviderID(_ id: String) async throws {
        try await self.modelRouter.setDefaultProviderID(id)
    }

    public func run(_ request: AgentRunRequest, timeoutMs: Int = 30_000) async throws -> AgentRunResult {
        let runID = request.runID
        let timeoutNs = UInt64(max(0, timeoutMs)) * 1_000_000

        return try await withThrowingTaskGroup(of: AgentRunResult.self) { group in
            group.addTask { [gatewayClient, toolRegistry, modelRouter] in
                var events: [AgentRunEvent] = [AgentRunEvent(runID: runID, kind: .runStarted)]
                var toolResults: [AgentToolResult] = []

                if await gatewayClient.isConnected() == false {
                    try await gatewayClient.connect(
                        to: GatewayEndpoint(url: URL(string: "ws://127.0.0.1:18789")!)
                    )
                }

                for call in request.toolCalls {
                    events.append(AgentRunEvent(runID: runID, kind: .toolStarted, toolName: call.name))
                    let toolResult = try await toolRegistry.execute(call)
                    toolResults.append(toolResult)
                    events.append(AgentRunEvent(runID: runID, kind: .toolCompleted, toolName: call.name))
                }

                _ = try await gatewayClient.send(method: "agent.run", params: [
                    "sessionKey": AnyCodable(request.sessionKey),
                    "prompt": AnyCodable(request.prompt),
                ])

                let modelResponse = try await modelRouter.generate(
                    ModelGenerationRequest(
                        sessionKey: request.sessionKey,
                        prompt: request.prompt,
                        providerID: request.modelProviderID
                    )
                )

                events.append(AgentRunEvent(runID: runID, kind: .runCompleted))
                return AgentRunResult(
                    runID: runID,
                    sessionKey: request.sessionKey,
                    output: modelResponse.text,
                    toolResults: toolResults,
                    events: events
                )
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNs)
                throw AgentRuntimeError.timedOut(runID: runID)
            }

            guard let result = try await group.next() else {
                throw AgentRuntimeError.timedOut(runID: runID)
            }
            group.cancelAll()
            return result
        }
    }
}

