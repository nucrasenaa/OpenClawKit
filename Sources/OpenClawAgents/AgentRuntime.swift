import Foundation
import OpenClawCore
import OpenClawGateway
import OpenClawModels
import OpenClawProtocol
import OpenClawSkills

/// Errors surfaced by the embedded agent runtime.
public enum AgentRuntimeError: Error, LocalizedError, Sendable {
    /// A requested tool name is not registered.
    case toolNotFound(String)
    /// A run exceeded the configured timeout window.
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

/// Timeline event emitted during agent run execution.
public struct AgentRunEvent: Sendable, Equatable {
    /// Event kinds emitted by a run.
    public enum Kind: String, Sendable {
        case runStarted
        case toolStarted
        case toolCompleted
        case runCompleted
    }

    public let runID: String
    public let kind: Kind
    public let toolName: String?

    /// Creates a run lifecycle event.
    /// - Parameters:
    ///   - runID: Correlated run identifier.
    ///   - kind: Event type.
    ///   - toolName: Optional tool associated with event.
    public init(runID: String, kind: Kind, toolName: String? = nil) {
        self.runID = runID
        self.kind = kind
        self.toolName = toolName
    }
}

/// Structured diagnostics event emitted by runtime/channel subsystems.
public struct RuntimeDiagnosticEvent: Sendable, Equatable {
    /// Event subsystem source (`runtime`, `channel`, etc.).
    public let subsystem: String
    /// Stable event name.
    public let name: String
    /// Optional correlated run identifier.
    public let runID: String?
    /// Optional correlated session key.
    public let sessionKey: String?
    /// Additional event metadata values.
    public let metadata: [String: String]

    /// Creates a diagnostics event.
    /// - Parameters:
    ///   - subsystem: Event subsystem.
    ///   - name: Event name.
    ///   - runID: Optional run identifier.
    ///   - sessionKey: Optional session key.
    ///   - metadata: Additional metadata.
    public init(
        subsystem: String,
        name: String,
        runID: String? = nil,
        sessionKey: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.subsystem = subsystem
        self.name = name
        self.runID = runID
        self.sessionKey = sessionKey
        self.metadata = metadata
    }
}

/// Async sink invoked for each runtime diagnostics event.
public typealias RuntimeDiagnosticSink = @Sendable (RuntimeDiagnosticEvent) async -> Void

/// Input payload for a single agent run.
public struct AgentRunRequest: Sendable {
    public let runID: String
    public let sessionKey: String
    public let prompt: String
    public let toolCalls: [AgentToolCall]
    public let modelProviderID: String?
    public let workspaceRootPath: String?

    /// Creates a run request.
    /// - Parameters:
    ///   - runID: Optional external run identifier.
    ///   - sessionKey: Session key used for routing/memory.
    ///   - prompt: User prompt payload.
    ///   - toolCalls: Ordered tool calls to execute before model generation.
    ///   - modelProviderID: Optional provider override.
    ///   - workspaceRootPath: Optional workspace root for skill/bootstrap prompt injection.
    public init(
        runID: String = UUID().uuidString,
        sessionKey: String,
        prompt: String,
        toolCalls: [AgentToolCall] = [],
        modelProviderID: String? = nil,
        workspaceRootPath: String? = nil
    ) {
        self.runID = runID
        self.sessionKey = sessionKey
        self.prompt = prompt
        self.toolCalls = toolCalls
        self.modelProviderID = modelProviderID
        self.workspaceRootPath = workspaceRootPath
    }
}

/// Output payload for a completed agent run.
public struct AgentRunResult: Sendable {
    public let runID: String
    public let sessionKey: String
    public let output: String
    public let toolResults: [AgentToolResult]
    public let events: [AgentRunEvent]

    /// Creates a run result.
    /// - Parameters:
    ///   - runID: Run identifier.
    ///   - sessionKey: Session key resolved for the run.
    ///   - output: Model output text.
    ///   - toolResults: Tool execution outputs.
    ///   - events: Lifecycle events emitted during run.
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

/// Actor that orchestrates tool execution, gateway lifecycle, and model generation.
public actor EmbeddedAgentRuntime {
    private let gatewayClient: GatewayClient
    private let toolRegistry: AgentToolRegistry
    private let modelRouter: ModelRouter

    /// Creates an embedded runtime.
    /// - Parameters:
    ///   - gatewayClient: Gateway transport client.
    ///   - toolRegistry: Registry used to resolve tool calls.
    ///   - modelRouter: Router for model provider selection.
    public init(
        gatewayClient: GatewayClient = GatewayClient(),
        toolRegistry: AgentToolRegistry = AgentToolRegistry(),
        modelRouter: ModelRouter = ModelRouter()
    ) {
        self.gatewayClient = gatewayClient
        self.toolRegistry = toolRegistry
        self.modelRouter = modelRouter
    }

    /// Registers a tool implementation for runtime use.
    /// - Parameter tool: Tool instance to register.
    public func registerTool(_ tool: any AgentTool) async {
        await self.toolRegistry.register(tool)
    }

    /// Registers a model provider for runtime routing.
    /// - Parameter provider: Provider implementation.
    public func registerModelProvider(_ provider: any ModelProvider) async {
        await self.modelRouter.register(provider)
    }

    /// Updates default model provider used when request does not specify one.
    /// - Parameter id: Registered provider identifier.
    public func setDefaultModelProviderID(_ id: String) async throws {
        try await self.modelRouter.setDefaultProviderID(id)
    }

    /// Executes an agent run with optional timeout protection.
    /// - Parameters:
    ///   - request: Run request payload.
    ///   - timeoutMs: Timeout in milliseconds.
    /// - Returns: Run result containing output, tool results, and lifecycle events.
    public func run(_ request: AgentRunRequest, timeoutMs: Int = 30_000) async throws -> AgentRunResult {
        let runID = request.runID
        let timeoutNs = UInt64(max(0, timeoutMs)) * 1_000_000

        return try await withThrowingTaskGroup(of: AgentRunResult.self) { group in
            group.addTask { [gatewayClient, toolRegistry, modelRouter] in
                var events: [AgentRunEvent] = [AgentRunEvent(runID: runID, kind: .runStarted)]
                var toolResults: [AgentToolResult] = []
                let composedPrompt = try await Self.composePrompt(
                    basePrompt: request.prompt,
                    workspaceRootPath: request.workspaceRootPath
                )

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
                    "prompt": AnyCodable(composedPrompt),
                ])

                let modelResponse = try await modelRouter.generate(
                    ModelGenerationRequest(
                        sessionKey: request.sessionKey,
                        prompt: composedPrompt,
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

    /// Builds the final prompt by combining bootstrap context, skills, and user text.
    /// - Parameters:
    ///   - basePrompt: Original user prompt.
    ///   - workspaceRootPath: Optional workspace path containing bootstrap/skills.
    /// - Returns: Prompt sent to model provider.
    private static func composePrompt(basePrompt: String, workspaceRootPath: String?) async throws -> String {
        guard let workspaceRootPath else {
            return basePrompt
        }
        let trimmed = workspaceRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return basePrompt
        }

        let registry = SkillRegistry(workspaceRoot: URL(fileURLWithPath: trimmed))
        let snapshot = try await registry.loadPromptSnapshot()
        let bootstrap = try await BootstrapContextLoader(
            workspaceRoot: URL(fileURLWithPath: trimmed)
        ).loadPromptSnapshot()
        let skillsPrompt = snapshot.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let bootstrapPrompt = bootstrap.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if skillsPrompt.isEmpty && bootstrapPrompt.isEmpty {
            return basePrompt
        }

        var sections: [String] = []
        if !bootstrapPrompt.isEmpty {
            sections.append(bootstrapPrompt)
        }
        if !skillsPrompt.isEmpty {
            sections.append(skillsPrompt)
        }
        sections.append("## User Request")
        sections.append(basePrompt)
        return sections.joined(separator: "\n\n")
    }
}

