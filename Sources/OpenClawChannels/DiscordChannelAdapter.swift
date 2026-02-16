import Foundation
import OpenClawCore

public protocol DiscordHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> HTTPResponseData
}

extension HTTPClient: DiscordHTTPTransport {}

private struct DiscordCurrentUser: Decodable {
    let id: String
}

private struct DiscordAuthor: Decodable {
    let id: String
    let bot: Bool?
}

private struct DiscordMessage: Decodable {
    let id: String
    let content: String
    let author: DiscordAuthor
}

public actor DiscordChannelAdapter: ChannelAdapter {
    public let id: ChannelID = .discord

    private let config: DiscordChannelConfig
    private let transport: any DiscordHTTPTransport
    private let baseURL: URL

    private var started = false
    private var pollTask: Task<Void, Never>?
    private var botUserID: String?
    private var lastSeenMessageID: UInt64?
    private var inboundHandler: (@Sendable (InboundMessage) async -> Void)?

    public init(
        config: DiscordChannelConfig,
        transport: any DiscordHTTPTransport = HTTPClient(),
        baseURL: URL = URL(string: "https://discord.com/api/v10")!
    ) {
        self.config = config
        self.transport = transport
        self.baseURL = baseURL
    }

    public func setInboundHandler(_ handler: (@Sendable (InboundMessage) async -> Void)?) {
        self.inboundHandler = handler
    }

    public func start() async throws {
        guard self.config.enabled else {
            throw OpenClawCoreError.unavailable("Discord channel is disabled")
        }
        if self.started {
            return
        }
        let token = try self.resolveToken()
        let channelID = try self.resolveDefaultChannelID()
        self.botUserID = try await self.fetchCurrentUserID(token: token)
        self.started = true

        self.pollTask = Task { [weak self] in
            await self?.pollLoop(channelID: channelID, token: token)
        }
    }

    public func stop() async {
        self.started = false
        self.pollTask?.cancel()
        self.pollTask = nil
    }

    public func send(_ message: OutboundMessage) async throws {
        guard self.started else {
            throw OpenClawCoreError.unavailable("Discord adapter is not started")
        }
        let token = try self.resolveToken()
        let channelID = try resolveTargetChannelID(from: message) ?? self.resolveDefaultChannelID()
        let payload = ["content": message.text]
        let body = try JSONEncoder().encode(payload)
        var request = URLRequest(url: self.baseURL.appending(path: "channels/\(channelID)/messages"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")

        let response = try await self.transport.data(for: request)
        if response.statusCode == 401 {
            throw OpenClawCoreError.unavailable("Discord authentication failed")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OpenClawCoreError.unavailable("Discord send failed with status \(response.statusCode)")
        }
    }

    private func resolveTargetChannelID(from message: OutboundMessage) -> String? {
        let candidate = message.peerID.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    private func pollLoop(channelID: String, token: String) async {
        while !Task.isCancelled && self.started {
            do {
                try await self.pollOnce(channelID: channelID, token: token)
            } catch {
                // Keep loop alive; callers can inspect upstream runtime state.
            }
            let sleepNs = UInt64(max(250, self.config.pollIntervalMs)) * 1_000_000
            try? await Task.sleep(nanoseconds: sleepNs)
        }
    }

    private func pollOnce(channelID: String, token: String) async throws {
        var components = URLComponents(
            url: self.baseURL.appending(path: "channels/\(channelID)/messages"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: "20")]
        guard let url = components?.url else {
            throw OpenClawCoreError.invalidConfiguration("Invalid Discord messages URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        let response = try await self.transport.data(for: request)
        if response.statusCode == 401 {
            throw OpenClawCoreError.unavailable("Discord authentication failed")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OpenClawCoreError.unavailable("Discord poll failed with status \(response.statusCode)")
        }

        let messages = try JSONDecoder().decode([DiscordMessage].self, from: response.body)
            .sorted { (UInt64($0.id) ?? 0) < (UInt64($1.id) ?? 0) }
        for message in messages {
            let messageID = UInt64(message.id) ?? 0
            if let lastSeen = self.lastSeenMessageID, messageID <= lastSeen {
                continue
            }
            self.lastSeenMessageID = max(self.lastSeenMessageID ?? 0, messageID)
            if message.author.bot == true || message.author.id == self.botUserID {
                continue
            }
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }
            let inbound = InboundMessage(channel: .discord, peerID: message.author.id, text: text)
            if let inboundHandler {
                await inboundHandler(inbound)
            }
        }
    }

    private func fetchCurrentUserID(token: String) async throws -> String {
        var request = URLRequest(url: self.baseURL.appending(path: "users/@me"))
        request.httpMethod = "GET"
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        let response = try await self.transport.data(for: request)
        if response.statusCode == 401 {
            throw OpenClawCoreError.unavailable("Discord authentication failed")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OpenClawCoreError.unavailable("Discord identity check failed with status \(response.statusCode)")
        }
        let me = try JSONDecoder().decode(DiscordCurrentUser.self, from: response.body)
        return me.id
    }

    private func resolveToken() throws -> String {
        guard let token = self.config.botToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            throw OpenClawCoreError.invalidConfiguration("Discord bot token is required")
        }
        return token
    }

    private func resolveDefaultChannelID() throws -> String {
        guard let channelID = self.config.defaultChannelID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !channelID.isEmpty
        else {
            throw OpenClawCoreError.invalidConfiguration("Discord default channel ID is required")
        }
        return channelID
    }
}
