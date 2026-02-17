import Foundation
import OpenClawAgents
import OpenClawCore
import OpenClawMemory
import OpenClawSkills

/// Stable channel identifiers supported by channel adapters.
public enum ChannelID: String, CaseIterable, Sendable {
    case whatsapp
    case telegram
    case slack
    case discord
    case signal
    case imessage
    case line
    case webchat
}

/// Normalized inbound message envelope delivered to the runtime.
public struct InboundMessage: Sendable, Equatable {
    public let channel: ChannelID
    public let accountID: String?
    public let peerID: String
    public let text: String

    /// Creates an inbound message envelope.
    /// - Parameters:
    ///   - channel: Source channel identifier.
    ///   - accountID: Optional account/user identifier.
    ///   - peerID: Conversation peer/channel identifier.
    ///   - text: Message content.
    public init(channel: ChannelID, accountID: String? = nil, peerID: String, text: String) {
        self.channel = channel
        self.accountID = accountID
        self.peerID = peerID
        self.text = text
    }
}

/// Normalized outbound message envelope sent through adapters.
public struct OutboundMessage: Sendable, Equatable {
    public let channel: ChannelID
    public let accountID: String?
    public let peerID: String
    public let text: String

    /// Creates an outbound message envelope.
    /// - Parameters:
    ///   - channel: Destination channel identifier.
    ///   - accountID: Optional account/user identifier.
    ///   - peerID: Conversation peer/channel identifier.
    ///   - text: Message content.
    public init(channel: ChannelID, accountID: String? = nil, peerID: String, text: String) {
        self.channel = channel
        self.accountID = accountID
        self.peerID = peerID
        self.text = text
    }
}

/// Async callback invoked for adapter-delivered inbound messages.
public typealias InboundMessageHandler = @Sendable (InboundMessage) async -> Void

/// Pluggable channel transport abstraction.
public protocol ChannelAdapter: Sendable {
    /// Channel identifier handled by this adapter.
    var id: ChannelID { get }
    /// Starts the adapter transport.
    func start() async throws
    /// Stops the adapter transport.
    func stop() async
    /// Sends an outbound message to the backing channel.
    /// - Parameter message: Outbound payload.
    func send(_ message: OutboundMessage) async throws
}

/// Optional adapter capability for channels that can push inbound messages.
public protocol InboundChannelAdapter: ChannelAdapter {
    /// Registers or clears the inbound message callback.
    /// - Parameter handler: Callback invoked when inbound messages are received.
    func setInboundHandler(_ handler: InboundMessageHandler?) async
}

/// Registry that tracks channel adapters and dispatches outbound sends.
public actor ChannelRegistry {
    private var adapters: [ChannelID: any ChannelAdapter] = [:]
    private var sentMessages: [OutboundMessage] = []

    /// Creates an empty channel registry.
    public init() {}

    /// Registers (or replaces) a channel adapter.
    /// - Parameter adapter: Adapter implementation.
    public func register(_ adapter: any ChannelAdapter) {
        self.adapters[adapter.id] = adapter
    }

    /// Returns whether an adapter exists for an ID.
    /// - Parameter id: Channel identifier.
    /// - Returns: `true` when adapter is registered.
    public func hasAdapter(id: ChannelID) -> Bool {
        self.adapters[id] != nil
    }

    /// Lists registered channel IDs in sorted order.
    /// - Returns: Sorted adapter channel IDs.
    public func adapterIDs() -> [ChannelID] {
        self.adapters.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Returns the adapter for a channel ID, if present.
    /// - Parameter id: Channel identifier.
    /// - Returns: Matching adapter or `nil`.
    public func adapter(for id: ChannelID) -> (any ChannelAdapter)? {
        self.adapters[id]
    }

    /// Sends an outbound message using the registered adapter.
    /// - Parameter message: Outbound message.
    public func send(_ message: OutboundMessage) async throws {
        guard let adapter = self.adapters[message.channel] else {
            throw OpenClawCoreError.unavailable("No adapter registered for \(message.channel.rawValue)")
        }
        try await adapter.send(message)
        self.sentMessages.append(message)
    }

    /// Returns outbound message history captured by registry dispatches.
    public func outboundHistory() -> [OutboundMessage] {
        self.sentMessages
    }
}

/// Lightweight in-memory adapter used for tests and local demos.
public actor InMemoryChannelAdapter: ChannelAdapter {
    public let id: ChannelID
    private(set) var started = false
    private var sent: [OutboundMessage] = []

    /// Creates an in-memory adapter bound to a channel ID.
    /// - Parameter id: Adapter channel identifier.
    public init(id: ChannelID) {
        self.id = id
    }

    /// Marks adapter as started.
    public func start() async throws {
        self.started = true
    }

    /// Marks adapter as stopped.
    public func stop() async {
        self.started = false
    }

    /// Captures an outbound message while started.
    /// - Parameter message: Outbound payload.
    public func send(_ message: OutboundMessage) async throws {
        guard self.started else {
            throw OpenClawCoreError.unavailable("Adapter \(self.id.rawValue) is not started")
        }
        self.sent.append(message)
    }

    /// Returns outbound messages captured by this adapter.
    public func sentMessages() -> [OutboundMessage] {
        self.sent
    }
}

/// End-to-end auto-reply pipeline coordinating routing, runtime, and outbound delivery.
public actor AutoReplyEngine {
    private let config: OpenClawConfig
    private let sessionStore: SessionStore
    private let channelRegistry: ChannelRegistry
    private let runtime: EmbeddedAgentRuntime
    private let conversationMemoryStore: ConversationMemoryStore?
    private let memoryContextLimit: Int
    private let diagnosticsSink: RuntimeDiagnosticSink?

    /// Creates an auto-reply engine.
    /// - Parameters:
    ///   - config: Runtime configuration.
    ///   - sessionStore: Session storage actor.
    ///   - channelRegistry: Adapter registry for outbound dispatch.
    ///   - runtime: Embedded runtime to execute prompts/tools.
    ///   - conversationMemoryStore: Optional persistent conversation memory store.
    ///   - memoryContextLimit: Number of turns included in prompt context.
    public init(
        config: OpenClawConfig,
        sessionStore: SessionStore,
        channelRegistry: ChannelRegistry,
        runtime: EmbeddedAgentRuntime,
        conversationMemoryStore: ConversationMemoryStore? = nil,
        memoryContextLimit: Int = 12,
        diagnosticsSink: RuntimeDiagnosticSink? = nil
    ) {
        self.config = config
        self.sessionStore = sessionStore
        self.channelRegistry = channelRegistry
        self.runtime = runtime
        self.conversationMemoryStore = conversationMemoryStore
        self.memoryContextLimit = max(1, memoryContextLimit)
        self.diagnosticsSink = diagnosticsSink
    }

    /// Processes an inbound message and returns the outbound response.
    /// - Parameter message: Inbound message envelope.
    /// - Returns: Outbound message delivered through channel registry.
    public func process(_ message: InboundMessage) async throws -> OutboundMessage {
        await self.emitDiagnostic(
            name: "inbound.received",
            sessionKey: nil,
            metadata: [
                "channel": message.channel.rawValue,
                "accountID": message.accountID ?? "",
                "peerID": message.peerID,
            ]
        )
        let routingContext = SessionRoutingContext(
            channel: message.channel.rawValue,
            accountID: message.accountID,
            peerID: message.peerID
        )
        let sessionKey = SessionKeyResolver.resolve(
            explicit: nil,
            context: routingContext,
            config: self.config
        )
        let resolvedAgentID = self.config.agents.resolvedAgentID(for: routingContext)
        await self.emitDiagnostic(
            name: "routing.session_resolved",
            sessionKey: sessionKey,
            metadata: [
                "agentID": resolvedAgentID,
                "channel": message.channel.rawValue,
            ]
        )

        _ = await self.sessionStore.resolveOrCreate(
            sessionKey: sessionKey,
            defaultAgentID: resolvedAgentID,
            route: SessionRoute(
                channel: message.channel.rawValue,
                accountID: message.accountID,
                peerID: message.peerID
            )
        )
        try await self.sessionStore.save()

        let memoryContext = await self.conversationMemoryStore?.formattedContext(
            sessionKey: sessionKey,
            limit: self.memoryContextLimit
        ) ?? ""
        await self.emitDiagnostic(
            name: "memory.context_loaded",
            sessionKey: sessionKey,
            metadata: ["contextLength": String(memoryContext.count)]
        )
        if let store = self.conversationMemoryStore {
            await store.appendUserTurn(
                sessionKey: sessionKey,
                channel: message.channel.rawValue,
                accountID: message.accountID,
                peerID: message.peerID,
                text: message.text
            )
            try await store.save()
        }
        let skillOutput = try await self.invokeSkillIfRequested(message.text)
        if let skillOutput {
            await self.emitDiagnostic(
                name: "skill.invoked",
                sessionKey: sessionKey,
                metadata: [
                    "skillName": skillOutput.skillName,
                    "outputLength": String(skillOutput.output.count),
                ]
            )
        }
        let runtimePrompt = Self.composeRuntimePrompt(
            memoryContext: memoryContext,
            inboundText: message.text,
            skillOutput: skillOutput
        )
        await self.emitDiagnostic(
            name: "model.call.started",
            sessionKey: sessionKey,
            metadata: ["providerID": self.config.models.defaultProviderID]
        )

        let result = try await self.runtime.run(
            AgentRunRequest(
                sessionKey: sessionKey,
                prompt: runtimePrompt,
                workspaceRootPath: self.config.agents.workspaceRoot
            )
        )

        let outbound = OutboundMessage(
            channel: message.channel,
            accountID: message.accountID,
            peerID: message.peerID,
            text: result.output
        )
        await self.emitDiagnostic(
            name: "runtime.completed",
            sessionKey: sessionKey,
            metadata: ["outputLength": String(result.output.count)]
        )
        await self.emitDiagnostic(
            name: "model.call.completed",
            sessionKey: sessionKey,
            metadata: ["outputLength": String(result.output.count)]
        )
        if let store = self.conversationMemoryStore {
            await store.appendAssistantTurn(
                sessionKey: sessionKey,
                channel: outbound.channel.rawValue,
                accountID: outbound.accountID,
                peerID: outbound.peerID,
                text: outbound.text
            )
            try await store.save()
        }
        await self.emitDiagnostic(
            name: "outbound.dispatching",
            sessionKey: sessionKey,
            metadata: [
                "channel": outbound.channel.rawValue,
                "peerID": outbound.peerID,
            ]
        )
        try await self.channelRegistry.send(outbound)
        await self.emitDiagnostic(
            name: "outbound.sent",
            sessionKey: sessionKey,
            metadata: [
                "channel": outbound.channel.rawValue,
                "peerID": outbound.peerID,
            ]
        )
        return outbound
    }

    private static func composeRuntimePrompt(
        memoryContext: String,
        inboundText: String,
        skillOutput: SkillInvocationResult?
    ) -> String {
        let context = memoryContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let skillText = skillOutput?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if context.isEmpty && skillText.isEmpty {
            return inboundText
        }

        var sections: [String] = []
        if !context.isEmpty {
            sections.append(context)
        }
        if let skillOutput, !skillText.isEmpty {
            sections.append("## Skill Output (\(skillOutput.skillName))\n\(skillText)")
        }
        sections.append("## New User Message\n\(inboundText)")
        return sections.joined(separator: "\n\n")
    }

    private func invokeSkillIfRequested(_ messageText: String) async throws -> SkillInvocationResult? {
        let workspaceRoot = self.config.agents.workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspaceRoot.isEmpty else {
            return nil
        }
        let invoker = SkillInvocationEngine(workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
        return try await invoker.invokeIfRequested(message: messageText)
    }

    private func emitDiagnostic(name: String, sessionKey: String?, metadata: [String: String] = [:]) async {
        guard let diagnosticsSink else { return }
        await diagnosticsSink(
            RuntimeDiagnosticEvent(
                subsystem: "channel",
                name: name,
                sessionKey: sessionKey,
                metadata: metadata
            )
        )
    }
}

