import Foundation
import OpenClawAgents
import OpenClawCore

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

public struct InboundMessage: Sendable, Equatable {
    public let channel: ChannelID
    public let accountID: String?
    public let peerID: String
    public let text: String

    public init(channel: ChannelID, accountID: String? = nil, peerID: String, text: String) {
        self.channel = channel
        self.accountID = accountID
        self.peerID = peerID
        self.text = text
    }
}

public struct OutboundMessage: Sendable, Equatable {
    public let channel: ChannelID
    public let accountID: String?
    public let peerID: String
    public let text: String

    public init(channel: ChannelID, accountID: String? = nil, peerID: String, text: String) {
        self.channel = channel
        self.accountID = accountID
        self.peerID = peerID
        self.text = text
    }
}

public protocol ChannelAdapter: Sendable {
    var id: ChannelID { get }
    func start() async throws
    func stop() async
    func send(_ message: OutboundMessage) async throws
}

public actor ChannelRegistry {
    private var adapters: [ChannelID: any ChannelAdapter] = [:]
    private var sentMessages: [OutboundMessage] = []

    public init() {}

    public func register(_ adapter: any ChannelAdapter) {
        self.adapters[adapter.id] = adapter
    }

    public func hasAdapter(id: ChannelID) -> Bool {
        self.adapters[id] != nil
    }

    public func adapterIDs() -> [ChannelID] {
        self.adapters.keys.sorted { $0.rawValue < $1.rawValue }
    }

    public func adapter(for id: ChannelID) -> (any ChannelAdapter)? {
        self.adapters[id]
    }

    public func send(_ message: OutboundMessage) async throws {
        guard let adapter = self.adapters[message.channel] else {
            throw OpenClawCoreError.unavailable("No adapter registered for \(message.channel.rawValue)")
        }
        try await adapter.send(message)
        self.sentMessages.append(message)
    }

    public func outboundHistory() -> [OutboundMessage] {
        self.sentMessages
    }
}

public actor InMemoryChannelAdapter: ChannelAdapter {
    public let id: ChannelID
    private(set) var started = false
    private var sent: [OutboundMessage] = []

    public init(id: ChannelID) {
        self.id = id
    }

    public func start() async throws {
        self.started = true
    }

    public func stop() async {
        self.started = false
    }

    public func send(_ message: OutboundMessage) async throws {
        guard self.started else {
            throw OpenClawCoreError.unavailable("Adapter \(self.id.rawValue) is not started")
        }
        self.sent.append(message)
    }

    public func sentMessages() -> [OutboundMessage] {
        self.sent
    }
}

public actor AutoReplyEngine {
    private let config: OpenClawConfig
    private let sessionStore: SessionStore
    private let channelRegistry: ChannelRegistry
    private let runtime: EmbeddedAgentRuntime

    public init(
        config: OpenClawConfig,
        sessionStore: SessionStore,
        channelRegistry: ChannelRegistry,
        runtime: EmbeddedAgentRuntime
    ) {
        self.config = config
        self.sessionStore = sessionStore
        self.channelRegistry = channelRegistry
        self.runtime = runtime
    }

    public func process(_ message: InboundMessage) async throws -> OutboundMessage {
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

        _ = await self.sessionStore.resolveOrCreate(
            sessionKey: sessionKey,
            defaultAgentID: self.config.agents.defaultAgentID,
            route: SessionRoute(
                channel: message.channel.rawValue,
                accountID: message.accountID,
                peerID: message.peerID
            )
        )
        try await self.sessionStore.save()

        let result = try await self.runtime.run(
            AgentRunRequest(
                sessionKey: sessionKey,
                prompt: message.text,
                workspaceRootPath: self.config.agents.workspaceRoot
            )
        )

        let outbound = OutboundMessage(
            channel: message.channel,
            accountID: message.accountID,
            peerID: message.peerID,
            text: result.output
        )
        try await self.channelRegistry.send(outbound)
        return outbound
    }
}

