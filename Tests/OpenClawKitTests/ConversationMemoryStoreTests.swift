import Foundation
import Testing
@testable import OpenClawKit

@Suite("Conversation memory store")
struct ConversationMemoryStoreTests {
    @Test
    func persistsAndLoadsSessionTurns() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-conversation-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storeURL = root.appendingPathComponent("conversation-memory.json", isDirectory: false)
        let store = ConversationMemoryStore(fileURL: storeURL)
        await store.appendUserTurn(
            sessionKey: "discord:user:channel",
            channel: "discord",
            accountID: "user",
            peerID: "channel",
            text: "hello"
        )
        await store.appendAssistantTurn(
            sessionKey: "discord:user:channel",
            channel: "discord",
            accountID: "user",
            peerID: "channel",
            text: "hi there"
        )
        try await store.save()

        let reloaded = ConversationMemoryStore(fileURL: storeURL)
        try await reloaded.load()
        let entries = await reloaded.recentEntries(sessionKey: "discord:user:channel", limit: 10)
        #expect(entries.count == 2)
        #expect(entries.first?.role == .user)
        #expect(entries.last?.role == .assistant)
    }

    @Test
    func formatsContextForPromptInjection() async throws {
        let store = ConversationMemoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        await store.appendUserTurn(
            sessionKey: "s",
            channel: "discord",
            accountID: "u",
            peerID: "p",
            text: "What did we discuss?"
        )
        await store.appendAssistantTurn(
            sessionKey: "s",
            channel: "discord",
            accountID: "u",
            peerID: "p",
            text: "We discussed deployment behavior."
        )

        let context = await store.formattedContext(sessionKey: "s", limit: 10)
        #expect(context.contains("## Conversation Memory Context"))
        #expect(context.contains("[user] What did we discuss?"))
        #expect(context.contains("[assistant] We discussed deployment behavior."))
    }
}
