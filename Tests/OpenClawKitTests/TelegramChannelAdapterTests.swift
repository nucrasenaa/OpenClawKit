import Foundation
import Testing
@testable import OpenClawKit

@Suite("Telegram channel adapter")
struct TelegramChannelAdapterTests {
    actor InboundCollector {
        private(set) var messages: [InboundMessage] = []

        func append(_ message: InboundMessage) {
            self.messages.append(message)
        }

        func snapshot() -> [InboundMessage] {
            self.messages
        }
    }

    actor MockTelegramTransport: TelegramHTTPTransport {
        struct RequestRecord: Sendable {
            let method: String
            let path: String
            let body: String
        }

        var requestRecords: [RequestRecord] = []
        var meStatusCode: Int
        var updateResponses: [Data]
        var sendStatusCode: Int
        var botUsername: String
        var botID: Int64

        init(
            meStatusCode: Int = 200,
            updateResponses: [Data] = [],
            sendStatusCode: Int = 200,
            botUsername: String = "OpenClawBot",
            botID: Int64 = 999
        ) {
            self.meStatusCode = meStatusCode
            self.updateResponses = updateResponses
            self.sendStatusCode = sendStatusCode
            self.botUsername = botUsername
            self.botID = botID
        }

        func data(for request: URLRequest) async throws -> HTTPResponseData {
            let record = RequestRecord(
                method: request.httpMethod ?? "GET",
                path: request.url?.path ?? "",
                body: String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            )
            self.requestRecords.append(record)

            if record.path.contains("/getMe") {
                guard self.meStatusCode == 200 else {
                    return HTTPResponseData(statusCode: self.meStatusCode, headers: [:], body: Data())
                }
                let payload = """
                {"ok":true,"result":{"id":\(self.botID),"is_bot":true,"username":"\(self.botUsername)"}}
                """
                return HTTPResponseData(statusCode: 200, headers: [:], body: Data(payload.utf8))
            }

            if record.path.contains("/getUpdates") {
                let body = self.updateResponses.isEmpty
                    ? Data("{\"ok\":true,\"result\":[]}".utf8)
                    : self.updateResponses.removeFirst()
                return HTTPResponseData(statusCode: 200, headers: [:], body: body)
            }

            if record.path.contains("/sendChatAction") {
                return HTTPResponseData(statusCode: 200, headers: [:], body: Data("{\"ok\":true,\"result\":true}".utf8))
            }

            if record.path.contains("/sendMessage") {
                guard self.sendStatusCode == 200 else {
                    return HTTPResponseData(statusCode: self.sendStatusCode, headers: [:], body: Data())
                }
                let payload = """
                {"ok":true,"result":{"message_id":1,"text":"ok","chat":{"id":123,"type":"private"}}}
                """
                return HTTPResponseData(statusCode: 200, headers: [:], body: Data(payload.utf8))
            }

            return HTTPResponseData(statusCode: 404, headers: [:], body: Data())
        }

        func records() -> [RequestRecord] {
            self.requestRecords
        }
    }

    @Test
    func pollsUpdatesAndDeliversInboundPrivateMessages() async throws {
        let updates = Data("""
        {"ok":true,"result":[{"update_id":1,"message":{"message_id":10,"text":"hello from tg","chat":{"id":111,"type":"private"},"from":{"id":42,"is_bot":false}}}]}
        """.utf8)
        let transport = MockTelegramTransport(updateResponses: [updates, Data("{\"ok\":true,\"result\":[]}".utf8)])
        let collector = InboundCollector()
        let adapter = TelegramChannelAdapter(
            config: TelegramChannelConfig(
                enabled: true,
                botToken: "token",
                pollIntervalMs: 250
            ),
            transport: transport,
            baseURL: URL(string: "https://telegram.example")!
        )
        await adapter.setInboundHandler { message in
            await collector.append(message)
        }

        try await adapter.start()
        try await Task.sleep(nanoseconds: 350_000_000)
        await adapter.stop()

        let messages = await collector.snapshot()
        #expect(messages.count >= 1)
        #expect(messages.first?.channel == .telegram)
        #expect(messages.first?.accountID == "42")
        #expect(messages.first?.peerID == "111")
        #expect(messages.first?.text == "hello from tg")
    }

    @Test
    func mentionOnlyModeFiltersGroupMessagesWithoutMentions() async throws {
        let updates = Data("""
        {"ok":true,"result":[
          {"update_id":5,"message":{"message_id":1,"text":"hello all","chat":{"id":-1001,"type":"group"},"from":{"id":10,"is_bot":false}}},
          {"update_id":6,"message":{"message_id":2,"text":"@OpenClawBot status please","chat":{"id":-1001,"type":"group"},"from":{"id":11,"is_bot":false}}}
        ]}
        """.utf8)
        let transport = MockTelegramTransport(updateResponses: [updates, Data("{\"ok\":true,\"result\":[]}".utf8)])
        let collector = InboundCollector()
        let adapter = TelegramChannelAdapter(
            config: TelegramChannelConfig(
                enabled: true,
                botToken: "token",
                pollIntervalMs: 250,
                mentionOnly: true
            ),
            transport: transport,
            baseURL: URL(string: "https://telegram.example")!
        )
        await adapter.setInboundHandler { message in
            await collector.append(message)
        }

        try await adapter.start()
        try await Task.sleep(nanoseconds: 350_000_000)
        await adapter.stop()

        let messages = await collector.snapshot()
        #expect(messages.count == 1)
        #expect(messages.first?.accountID == "11")
        #expect(messages.first?.text.contains("status please") == true)
    }

    @Test
    func sendPostsOutboundMessage() async throws {
        let transport = MockTelegramTransport(updateResponses: [Data("{\"ok\":true,\"result\":[]}".utf8)])
        let adapter = TelegramChannelAdapter(
            config: TelegramChannelConfig(
                enabled: true,
                botToken: "token",
                defaultChatID: "222",
                pollIntervalMs: 250
            ),
            transport: transport,
            baseURL: URL(string: "https://telegram.example")!
        )

        try await adapter.start()
        try await adapter.send(OutboundMessage(channel: .telegram, peerID: "222", text: "hello outbound"))
        await adapter.stop()

        let records = await transport.records()
        #expect(records.contains(where: { $0.method == "POST" && $0.path.contains("/sendMessage") }))
        #expect(records.contains(where: { $0.body.contains("hello outbound") }))
    }

    @Test
    func startFailsWhenGetMeIsUnauthorized() async throws {
        let transport = MockTelegramTransport(meStatusCode: 401)
        let adapter = TelegramChannelAdapter(
            config: TelegramChannelConfig(
                enabled: true,
                botToken: "bad-token",
                pollIntervalMs: 250
            ),
            transport: transport,
            baseURL: URL(string: "https://telegram.example")!
        )

        do {
            try await adapter.start()
            Issue.record("Expected auth failure")
        } catch {
            #expect(String(describing: error).lowercased().contains("status"))
        }
    }
}
