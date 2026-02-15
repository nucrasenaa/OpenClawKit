import Foundation
import Testing
@testable import OpenClawKit

@Suite("Channels and auto-reply")
struct ChannelAutoReplyTests {
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
}

