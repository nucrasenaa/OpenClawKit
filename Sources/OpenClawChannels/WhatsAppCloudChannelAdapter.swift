import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OpenClawCore

/// Minimal HTTP transport contract used by the WhatsApp Cloud adapter.
public protocol WhatsAppCloudHTTPTransport: Sendable {
    /// Executes an HTTP request and returns normalized response payload.
    /// - Parameter request: Configured URL request.
    /// - Returns: Normalized response data.
    func data(for request: URLRequest) async throws -> HTTPResponseData
}

extension HTTPClient: WhatsAppCloudHTTPTransport {}

private struct WhatsAppSendTextRequest: Encodable {
    let messagingProduct = "whatsapp"
    let to: String
    let type = "text"
    let text: TextBody

    struct TextBody: Encodable {
        let body: String
    }

    private enum CodingKeys: String, CodingKey {
        case messagingProduct = "messaging_product"
        case to
        case type
        case text
    }
}

private struct WhatsAppWebhookPayload: Decodable {
    let entry: [Entry]

    struct Entry: Decodable {
        let changes: [Change]
    }

    struct Change: Decodable {
        let value: ValuePayload
    }

    struct ValuePayload: Decodable {
        let metadata: Metadata?
        let contacts: [Contact]?
        let messages: [Message]?
    }

    struct Metadata: Decodable {
        let phoneNumberID: String?

        private enum CodingKeys: String, CodingKey {
            case phoneNumberID = "phone_number_id"
        }
    }

    struct Contact: Decodable {
        let waID: String?

        private enum CodingKeys: String, CodingKey {
            case waID = "wa_id"
        }
    }

    struct Message: Decodable {
        let from: String?
        let text: MessageText?
        let type: String?
    }

    struct MessageText: Decodable {
        let body: String?
    }
}

/// WhatsApp Cloud API channel adapter using Graph API transport.
public actor WhatsAppCloudChannelAdapter: InboundChannelAdapter {
    /// Adapter channel identifier.
    public let id: ChannelID = .whatsapp

    private let config: WhatsAppCloudChannelConfig
    private let transport: any WhatsAppCloudHTTPTransport
    private let explicitBaseURL: URL?

    private var started = false
    private var inboundHandler: InboundMessageHandler?

    /// Creates a WhatsApp Cloud adapter.
    /// - Parameters:
    ///   - config: WhatsApp Cloud channel configuration.
    ///   - transport: HTTP transport implementation.
    ///   - baseURL: Optional Graph API base URL override.
    public init(
        config: WhatsAppCloudChannelConfig,
        transport: any WhatsAppCloudHTTPTransport = HTTPClient(),
        baseURL: URL? = nil
    ) {
        self.config = config
        self.transport = transport
        self.explicitBaseURL = baseURL
    }

    /// Registers or clears inbound webhook callback.
    /// - Parameter handler: Optional inbound callback.
    public func setInboundHandler(_ handler: InboundMessageHandler?) async {
        self.inboundHandler = handler
    }

    /// Starts adapter lifecycle.
    public func start() async throws {
        guard self.config.enabled else {
            throw OpenClawCoreError.unavailable("WhatsApp Cloud channel is disabled")
        }
        _ = try self.resolveAccessToken()
        _ = try self.resolvePhoneNumberID()
        self.started = true
    }

    /// Stops adapter lifecycle.
    public func stop() async {
        self.started = false
    }

    /// Sends outbound text message through WhatsApp Cloud API.
    /// - Parameter message: Outbound payload.
    public func send(_ message: OutboundMessage) async throws {
        guard self.started else {
            throw OpenClawCoreError.unavailable("WhatsApp Cloud adapter is not started")
        }
        let to = try self.resolveRecipient(from: message)
        let requestBody = WhatsAppSendTextRequest(to: to, text: .init(body: message.text))
        let endpoint = try self.resolveMessagesEndpoint()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try self.resolveAccessToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let response = try await self.transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw OpenClawCoreError.unavailable("WhatsApp Cloud send failed with status \(response.statusCode)")
        }
    }

    /// Handles webhook verification challenge request.
    /// - Parameters:
    ///   - mode: verify mode query value.
    ///   - token: verify token query value.
    ///   - challenge: challenge query value.
    /// - Returns: Echoed challenge when verification succeeds.
    public func handleWebhookVerification(mode: String?, token: String?, challenge: String?) -> String? {
        guard mode == "subscribe",
              let token,
              let challenge,
              let configured = self.config.webhookVerifyToken,
              !configured.isEmpty,
              configured == token
        else {
            return nil
        }
        return challenge
    }

    /// Handles incoming WhatsApp webhook event payload.
    /// - Parameter payload: Raw webhook JSON payload.
    public func handleWebhookEvent(_ payload: Data) async throws {
        guard self.started else {
            throw OpenClawCoreError.unavailable("WhatsApp Cloud adapter is not started")
        }

        let event = try JSONDecoder().decode(WhatsAppWebhookPayload.self, from: payload)
        for entry in event.entry {
            for change in entry.changes {
                let value = change.value
                let fallbackPeer = value.contacts?.first?.waID
                let accountID = value.metadata?.phoneNumberID ?? self.config.phoneNumberID
                for message in value.messages ?? [] {
                    guard message.type == nil || message.type == "text" else { continue }
                    guard let peerID = message.from ?? fallbackPeer else { continue }
                    guard let text = message.text?.body?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }

                    let inbound = InboundMessage(
                        channel: .whatsapp,
                        accountID: accountID,
                        peerID: peerID,
                        text: text
                    )
                    if let inboundHandler {
                        await inboundHandler(inbound)
                    }
                }
            }
        }
    }

    private func resolveAccessToken() throws -> String {
        guard let token = self.config.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw OpenClawCoreError.invalidConfiguration("WhatsApp Cloud access token is required")
        }
        return token
    }

    private func resolvePhoneNumberID() throws -> String {
        guard let id = self.config.phoneNumberID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw OpenClawCoreError.invalidConfiguration("WhatsApp Cloud phone number ID is required")
        }
        return id
    }

    private func resolveRecipient(from message: OutboundMessage) throws -> String {
        let candidate = message.peerID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty {
            return candidate
        }
        let fallback = message.accountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !fallback.isEmpty else {
            throw OpenClawCoreError.invalidConfiguration("WhatsApp recipient is required")
        }
        return fallback
    }

    private func resolveMessagesEndpoint() throws -> URL {
        let baseRaw = self.explicitBaseURL?.absoluteString ?? self.config.baseURL
        let base = baseRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let baseURL = URL(string: base) else {
            throw OpenClawCoreError.invalidConfiguration("WhatsApp Cloud base URL is invalid")
        }
        return baseURL
            .appendingPathComponent(self.config.apiVersion)
            .appendingPathComponent(try self.resolvePhoneNumberID())
            .appendingPathComponent("messages")
    }
}
