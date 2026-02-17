import Foundation
import Testing
@testable import OpenClawKit

@Suite("Channels and auto-reply")
struct ChannelAutoReplyTests {
    struct PromptEchoProvider: ModelProvider {
        let id = "prompt-echo"

        func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
            ModelGenerationResponse(text: request.prompt, providerID: self.id, modelID: "prompt-echo")
        }
    }

    actor DiagnosticCollector {
        private(set) var events: [RuntimeDiagnosticEvent] = []

        func append(_ event: RuntimeDiagnosticEvent) {
            self.events.append(event)
        }

        func names() -> [String] {
            self.events.map(\.name)
        }
    }

    @Test
    func channelRegistryRoutesMessagesByChannelID() async throws {
        let registry = ChannelRegistry()
        let telegram = InMemoryChannelAdapter(id: .telegram)
        await registry.register(telegram)
        try await telegram.start()

        let outbound = OutboundMessage(channel: .telegram, accountID: "default", peerID: "123", text: "hello")
        try await registry.send(outbound)

        let sent = await telegram.sentMessages()
        #expect(sent.count == 1)
        #expect(sent.first?.text == "hello")
    }

    @Test
    func autoReplyEnginePersistsSessionAndDeliversReply() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-autoreply-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sessionsPath = root.appendingPathComponent("sessions.json", isDirectory: false)

        let config = OpenClawConfig()
        let sessionStore = SessionStore(fileURL: sessionsPath)
        let registry = ChannelRegistry()
        let whatsapp = InMemoryChannelAdapter(id: .whatsapp)
        await registry.register(whatsapp)
        try await whatsapp.start()

        let runtime = EmbeddedAgentRuntime()
        let engine = AutoReplyEngine(
            config: config,
            sessionStore: sessionStore,
            channelRegistry: registry,
            runtime: runtime
        )

        let inbound = InboundMessage(channel: .whatsapp, accountID: "default", peerID: "555123", text: "hi")
        let outbound = try await engine.process(inbound)

        #expect(outbound.channel == .whatsapp)
        #expect(outbound.text == "OK")

        let allSessions = await sessionStore.allRecords()
        #expect(allSessions.count == 1)
        #expect(allSessions.first?.key.contains("whatsapp") == true)
    }

    @Test
    func autoReplyEngineUsesMappedAgentForRoute() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-autoreply-agent-route-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sessionsPath = root.appendingPathComponent("sessions.json", isDirectory: false)

        let config = OpenClawConfig(
            agents: AgentsConfig(
                defaultAgentID: "main",
                workspaceRoot: "./workspace",
                agentIDs: ["main", "support"],
                routeAgentMap: [
                    AgentsConfig.routeKey(channel: "whatsapp"): "support",
                ]
            )
        )
        let sessionStore = SessionStore(fileURL: sessionsPath)
        let registry = ChannelRegistry()
        let whatsapp = InMemoryChannelAdapter(id: .whatsapp)
        await registry.register(whatsapp)
        try await whatsapp.start()

        let runtime = EmbeddedAgentRuntime()
        let engine = AutoReplyEngine(
            config: config,
            sessionStore: sessionStore,
            channelRegistry: registry,
            runtime: runtime
        )
        let inbound = InboundMessage(channel: .whatsapp, accountID: "default", peerID: "555123", text: "hi")
        _ = try await engine.process(inbound)

        let key = SessionKeyResolver.resolve(
            explicit: nil,
            context: SessionRoutingContext(channel: "whatsapp", accountID: "default", peerID: "555123"),
            config: config
        )
        let record = await sessionStore.recordForKey(key)
        #expect(record?.agentID == "support")
    }

    @Test
    func autoReplyEngineInjectsPersistentConversationContext() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-autoreply-memory-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionsPath = root.appendingPathComponent("sessions.json", isDirectory: false)
        let memoryPath = root.appendingPathComponent("conversation-memory.json", isDirectory: false)
        let sessionStore = SessionStore(fileURL: sessionsPath)
        let memoryStore = ConversationMemoryStore(fileURL: memoryPath)
        try await sessionStore.load()
        try await memoryStore.load()

        let registry = ChannelRegistry()
        let webchat = InMemoryChannelAdapter(id: .webchat)
        await registry.register(webchat)
        try await webchat.start()

        let runtime = EmbeddedAgentRuntime()
        await runtime.registerModelProvider(PromptEchoProvider())
        try await runtime.setDefaultModelProviderID("prompt-echo")

        let engine = AutoReplyEngine(
            config: OpenClawConfig(),
            sessionStore: sessionStore,
            channelRegistry: registry,
            runtime: runtime,
            conversationMemoryStore: memoryStore,
            memoryContextLimit: 12
        )

        _ = try await engine.process(
            InboundMessage(channel: .webchat, accountID: "user-1", peerID: "peer", text: "first question")
        )
        let second = try await engine.process(
            InboundMessage(channel: .webchat, accountID: "user-1", peerID: "peer", text: "second question")
        )

        #expect(second.text.contains("## Conversation Memory Context"))
        #expect(second.text.contains("[user] first question"))
        #expect(second.text.contains("## New User Message"))
        #expect(second.text.contains("second question"))
    }

    @Test
    func autoReplyEngineEmitsChannelDiagnostics() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-autoreply-diagnostics-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionsPath = root.appendingPathComponent("sessions.json", isDirectory: false)
        let sessionStore = SessionStore(fileURL: sessionsPath)
        let registry = ChannelRegistry()
        let webchat = InMemoryChannelAdapter(id: .webchat)
        await registry.register(webchat)
        try await webchat.start()

        let collector = DiagnosticCollector()
        let runtime = EmbeddedAgentRuntime()
        let engine = AutoReplyEngine(
            config: OpenClawConfig(),
            sessionStore: sessionStore,
            channelRegistry: registry,
            runtime: runtime,
            diagnosticsSink: { event in
                await collector.append(event)
            }
        )

        _ = try await engine.process(
            InboundMessage(channel: .webchat, accountID: "user-1", peerID: "peer", text: "hello")
        )

        let names = await collector.names()
        #expect(names.contains("inbound.received"))
        #expect(names.contains("routing.session_resolved"))
        #expect(names.contains("model.call.started"))
        #expect(names.contains("model.call.completed"))
        #expect(names.contains("outbound.sent"))
    }
}

