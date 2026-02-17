import Foundation
import Testing
@testable import OpenClawKit

@Suite("WhatsApp Cloud channel adapter")
struct WhatsAppCloudChannelAdapterTests {
    actor InboundCollector {
        private(set) var messages: [InboundMessage] = []

        func append(_ message: InboundMessage) {
            self.messages.append(message)
        }

        func snapshot() -> [InboundMessage] {
            self.messages
        }
    }

    actor MockWhatsAppTransport: WhatsAppCloudHTTPTransport {
        struct RequestRecord: Sendable {
            let method: String
            let path: String
            let authorization: String?
            let body: String
        }

        var statusCode: Int = 200
        private(set) var records: [RequestRecord] = []

        func data(for request: URLRequest) async throws -> HTTPResponseData {
            self.records.append(
                RequestRecord(
                    method: request.httpMethod ?? "GET",
                    path: request.url?.path ?? "",
                    authorization: request.value(forHTTPHeaderField: "Authorization"),
                    body: String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                )
            )
            return HTTPResponseData(statusCode: self.statusCode, headers: [:], body: Data("{\"messages\":[]}".utf8))
        }

        func snapshot() -> [RequestRecord] {
            self.records
        }
    }

    @Test
    func sendPostsOutboundCloudAPIMessage() async throws {
        let transport = MockWhatsAppTransport()
        let adapter = WhatsAppCloudChannelAdapter(
            config: WhatsAppCloudChannelConfig(
                enabled: true,
                accessToken: "wa-token",
                phoneNumberID: "123456",
                webhookVerifyToken: "verify"
            ),
            transport: transport,
            baseURL: URL(string: "https://graph.example")!
        )
        try await adapter.start()
        try await adapter.send(
            OutboundMessage(channel: .whatsapp, accountID: "123456", peerID: "15551234567", text: "hello from openclaw")
        )
        await adapter.stop()

        let requests = await transport.snapshot()
        #expect(requests.count == 1)
        #expect(requests.first?.method == "POST")
        #expect(requests.first?.path.contains("/v20.0/123456/messages") == true)
        #expect(requests.first?.authorization == "Bearer wa-token")
        #expect(requests.first?.body.contains("\"messaging_product\":\"whatsapp\"") == true)
        #expect(requests.first?.body.contains("\"to\":\"15551234567\"") == true)
    }

    @Test
    func startFailsWhenAccessTokenMissing() async throws {
        let adapter = WhatsAppCloudChannelAdapter(
            config: WhatsAppCloudChannelConfig(
                enabled: true,
                accessToken: nil,
                phoneNumberID: "123456"
            ),
            transport: MockWhatsAppTransport(),
            baseURL: URL(string: "https://graph.example")!
        )

        do {
            try await adapter.start()
            Issue.record("Expected invalid configuration error")
        } catch {
            #expect(String(describing: error).contains("access token"))
        }
    }

    @Test
    func webhookVerificationEchoesChallengeWhenTokenMatches() async throws {
        let adapter = WhatsAppCloudChannelAdapter(
            config: WhatsAppCloudChannelConfig(
                enabled: true,
                accessToken: "wa-token",
                phoneNumberID: "123456",
                webhookVerifyToken: "verify"
            ),
            transport: MockWhatsAppTransport(),
            baseURL: URL(string: "https://graph.example")!
        )
        #expect(await adapter.handleWebhookVerification(mode: "subscribe", token: "verify", challenge: "1234") == "1234")
        #expect(await adapter.handleWebhookVerification(mode: "subscribe", token: "bad", challenge: "1234") == nil)
    }

    @Test
    func webhookEventDeliversInboundTextMessages() async throws {
        let collector = InboundCollector()
        let adapter = WhatsAppCloudChannelAdapter(
            config: WhatsAppCloudChannelConfig(
                enabled: true,
                accessToken: "wa-token",
                phoneNumberID: "123456",
                webhookVerifyToken: "verify"
            ),
            transport: MockWhatsAppTransport(),
            baseURL: URL(string: "https://graph.example")!
        )
        await adapter.setInboundHandler { message in
            await collector.append(message)
        }
        try await adapter.start()

        let webhook = Data("""
        {
          "entry": [
            {
              "changes": [
                {
                  "value": {
                    "metadata": { "phone_number_id": "123456" },
                    "contacts": [{ "wa_id": "15550001111" }],
                    "messages": [
                      {
                        "from": "15550001111",
                        "type": "text",
                        "text": { "body": "weather in milan?" }
                      }
                    ]
                  }
                }
              ]
            }
          ]
        }
        """.utf8)
        try await adapter.handleWebhookEvent(webhook)
        await adapter.stop()

        let messages = await collector.snapshot()
        #expect(messages.count == 1)
        #expect(messages.first?.channel == .whatsapp)
        #expect(messages.first?.accountID == "123456")
        #expect(messages.first?.peerID == "15550001111")
        #expect(messages.first?.text == "weather in milan?")
    }
}
