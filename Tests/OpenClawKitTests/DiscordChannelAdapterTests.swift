import Foundation
import Testing
@testable import OpenClawKit

@Suite("Discord channel adapter")
struct DiscordChannelAdapterTests {
    actor InboundCollector {
        private(set) var messages: [InboundMessage] = []

        func append(_ message: InboundMessage) {
            self.messages.append(message)
        }

        func snapshot() -> [InboundMessage] {
            self.messages
        }
    }

    actor MockDiscordTransport: DiscordHTTPTransport {
        struct RequestRecord: Sendable {
            let method: String
            let path: String
            let body: String
        }

        var requestRecords: [RequestRecord] = []
        var meStatusCode: Int
        var messagesQueue: [Data]
        var postStatusCode: Int
        let botUserID: String

        init(
            botUserID: String = "bot-id",
            meStatusCode: Int = 200,
            messagesQueue: [Data] = [],
            postStatusCode: Int = 200
        ) {
            self.botUserID = botUserID
            self.meStatusCode = meStatusCode
            self.messagesQueue = messagesQueue
            self.postStatusCode = postStatusCode
        }

        func data(for request: URLRequest) async throws -> HTTPResponseData {
            let record = RequestRecord(
                method: request.httpMethod ?? "GET",
                path: request.url?.path ?? "",
                body: String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            )
            self.requestRecords.append(record)

            if record.path.hasSuffix("/users/@me") {
                if self.meStatusCode == 200 {
                    let body = try JSONEncoder().encode(["id": self.botUserID])
                    return HTTPResponseData(statusCode: 200, headers: [:], body: body)
                }
                return HTTPResponseData(statusCode: self.meStatusCode, headers: [:], body: Data())
            }

            if record.path.contains("/messages"), record.method == "GET" {
                let body = self.messagesQueue.isEmpty ? Data("[]".utf8) : self.messagesQueue.removeFirst()
                return HTTPResponseData(statusCode: 200, headers: [:], body: body)
            }

            if record.path.contains("/messages"), record.method == "POST" {
                return HTTPResponseData(statusCode: self.postStatusCode, headers: [:], body: Data("{}".utf8))
            }

            return HTTPResponseData(statusCode: 404, headers: [:], body: Data())
        }

        func records() -> [RequestRecord] {
            self.requestRecords
        }
    }

    @Test
    func pollsMessagesAndDeliversInboundUserText() async throws {
        let payload = Data("""
        [
          {"id":"1","content":"hello from user","author":{"id":"user-1","bot":false}},
          {"id":"2","content":"ignore self","author":{"id":"bot-id","bot":true}}
        ]
        """.utf8)
        let transport = MockDiscordTransport(messagesQueue: [payload, Data("[]".utf8)])
        let collector = InboundCollector()
        let adapter = DiscordChannelAdapter(
            config: DiscordChannelConfig(
                enabled: true,
                botToken: "secret-token",
                defaultChannelID: "channel-1",
                pollIntervalMs: 250
            ),
            transport: transport,
            baseURL: URL(string: "https://discord.example/api/v10")!
        )
        await adapter.setInboundHandler { message in
            await collector.append(message)
        }

        try await adapter.start()
        try await Task.sleep(nanoseconds: 350_000_000)
        await adapter.stop()

        let received = await collector.snapshot()
        #expect(received.count >= 1)
        #expect(received.first?.channel == .discord)
        #expect(received.first?.peerID == "user-1")
        #expect(received.first?.text == "hello from user")
    }

    @Test
    func sendPostsOutboundMessageToDiscordChannel() async throws {
        let transport = MockDiscordTransport(messagesQueue: [Data("[]".utf8)])
        let adapter = DiscordChannelAdapter(
            config: DiscordChannelConfig(
                enabled: true,
                botToken: "secret-token",
                defaultChannelID: "channel-1",
                pollIntervalMs: 250
            ),
            transport: transport,
            baseURL: URL(string: "https://discord.example/api/v10")!
        )

        try await adapter.start()
        try await adapter.send(
            OutboundMessage(channel: .discord, peerID: "channel-1", text: "hello outbound")
        )
        await adapter.stop()

        let records = await transport.records()
        #expect(records.contains(where: { $0.method == "POST" && $0.path.hasSuffix("/channels/channel-1/messages") }))
        #expect(records.contains(where: { $0.body.contains("hello outbound") }))
    }

    @Test
    func startFailsWithAuthenticationErrorWhenTokenRejected() async throws {
        let transport = MockDiscordTransport(meStatusCode: 401)
        let adapter = DiscordChannelAdapter(
            config: DiscordChannelConfig(
                enabled: true,
                botToken: "bad-token",
                defaultChannelID: "channel-1",
                pollIntervalMs: 250
            ),
            transport: transport,
            baseURL: URL(string: "https://discord.example/api/v10")!
        )

        do {
            try await adapter.start()
            Issue.record("Expected auth failure")
        } catch {
            #expect(String(describing: error).lowercased().contains("authentication"))
        }
    }
}
