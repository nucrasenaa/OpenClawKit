import Foundation
import OpenClawKit
import Combine
import SwiftUI

@MainActor
final class OpenClawAppState: ObservableObject {
    enum DeploymentState: String, Sendable {
        case stopped
        case starting
        case running
        case stopping
        case failed
    }

    enum MessageRole: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
        let id: UUID
        let role: MessageRole
        let text: String
        let createdAt: Date

        init(id: UUID = UUID(), role: MessageRole, text: String, createdAt: Date = Date()) {
            self.id = id
            self.role = role
            self.text = text
            self.createdAt = createdAt
        }
    }

    struct PersistedSettings: Codable, Sendable {
        var discordBotToken: String
        var discordChannelID: String
        var openAIAPIKey: String
        var personality: String
    }

    @Published var discordBotToken: String = ""
    @Published var discordChannelID: String = ""
    @Published var openAIAPIKey: String = ""
    @Published var personality: String = ""
    @Published var pendingMessage: String = ""

    @Published private(set) var deploymentState: DeploymentState = .stopped
    @Published private(set) var statusText: String = "Not deployed"
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var latestSummary: String = ""

    var isDeployed: Bool {
        self.deploymentState == .running
    }

    private let sdk = OpenClawSDK.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let summaryScheduler = CronScheduler()
    private let memoryIndex = MemoryIndex()

    private let stateRoot: URL
    private let workspaceURL: URL
    private let configURL: URL
    private let sessionsURL: URL
    private let messagesURL: URL
    private let settingsURL: URL

    private var webchatAdapter: InMemoryChannelAdapter?
    private var discordAdapter: DiscordChannelAdapter?
    private var replyEngine: AutoReplyEngine?
    private var summaryTask: Task<Void, Never>?

    init() {
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory())
        self.stateRoot = docs.appendingPathComponent("OpenClawDemo", isDirectory: true)
        self.workspaceURL = self.stateRoot.appendingPathComponent("workspace", isDirectory: true)
        self.configURL = self.stateRoot.appendingPathComponent("config.json")
        self.sessionsURL = self.stateRoot.appendingPathComponent("sessions.json")
        self.messagesURL = self.stateRoot.appendingPathComponent("chat-messages.json")
        self.settingsURL = self.stateRoot.appendingPathComponent("deploy-settings.json")

        self.loadPersistedSettings()
        self.loadPersistedMessages()
    }

    func deploy() async {
        guard self.deploymentState != .starting, self.deploymentState != .running else { return }
        self.deploymentState = .starting
        self.statusText = "Starting deployment..."

        do {
            try FileManager.default.createDirectory(at: self.stateRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: self.workspaceURL, withIntermediateDirectories: true)
            try self.persistBootstrapFiles()

            let discordConfig = DiscordChannelConfig(
                enabled: !self.discordBotToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !self.discordChannelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                botToken: normalized(self.discordBotToken),
                defaultChannelID: normalized(self.discordChannelID),
                pollIntervalMs: 2_000
            )

            let config = OpenClawConfig(
                agents: AgentsConfig(defaultAgentID: "main", workspaceRoot: self.workspaceURL.path),
                channels: ChannelsConfig(discord: discordConfig),
                models: ModelsConfig(
                    defaultProviderID: "echo",
                    openAI: OpenAIModelConfig(
                        enabled: !self.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        apiKey: normalized(self.openAIAPIKey)
                    )
                )
            )

            try await self.sdk.saveConfig(config, to: self.configURL)
            try self.persistSettings()

            let sessionStore = SessionStore(fileURL: self.sessionsURL)
            try await sessionStore.load()

            let channelRegistry = ChannelRegistry()
            let webchat = InMemoryChannelAdapter(id: .webchat)
            await channelRegistry.register(webchat)
            try await webchat.start()

            let runtime = EmbeddedAgentRuntime()
            let replyEngine = AutoReplyEngine(
                config: config,
                sessionStore: sessionStore,
                channelRegistry: channelRegistry,
                runtime: runtime
            )

            if discordConfig.enabled {
                let discord = DiscordChannelAdapter(config: discordConfig)
                await discord.setInboundHandler { [replyEngine] inbound in
                    _ = try? await replyEngine.process(inbound)
                }
                await channelRegistry.register(discord)
                try await discord.start()
                self.discordAdapter = discord
            } else {
                self.discordAdapter = nil
            }

            self.webchatAdapter = webchat
            self.replyEngine = replyEngine

            await self.summaryScheduler.addOrUpdate(
                CronJob(
                    id: "chat-summary",
                    intervalSeconds: 60,
                    payload: "summary",
                    nextRunAt: Date().addingTimeInterval(60)
                )
            )
            self.startSummaryLoop()

            self.deploymentState = .running
            self.statusText = self.discordAdapter == nil
                ? "Deployment running (local chat only)."
                : "Deployment running (Discord + local chat)."
        } catch {
            self.deploymentState = .failed
            self.statusText = "Deployment failed: \(error.localizedDescription)"
        }
    }

    func stopDeployment() async {
        guard self.deploymentState == .running || self.deploymentState == .failed else { return }
        self.deploymentState = .stopping
        self.statusText = "Stopping deployment..."

        self.summaryTask?.cancel()
        self.summaryTask = nil

        if let discordAdapter {
            await discordAdapter.stop()
        }
        if let webchatAdapter {
            await webchatAdapter.stop()
        }

        self.discordAdapter = nil
        self.webchatAdapter = nil
        self.replyEngine = nil
        self.deploymentState = .stopped
        self.statusText = "Deployment stopped."
    }

    func sendPendingMessage() async {
        let text = self.pendingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        self.pendingMessage = ""
        await self.sendMessage(text)
    }

    func sendMessage(_ text: String) async {
        guard let replyEngine, self.deploymentState == .running else {
            self.statusText = "Deploy the agent before sending messages."
            return
        }

        self.appendMessage(.init(role: .user, text: text))
        do {
            let outbound = try await replyEngine.process(
                InboundMessage(channel: .webchat, peerID: "ios-local-user", text: text)
            )
            self.appendMessage(.init(role: .assistant, text: outbound.text))
        } catch {
            self.appendMessage(.init(role: .system, text: "Error: \(error.localizedDescription)"))
        }
    }

    private func startSummaryLoop() {
        self.summaryTask?.cancel()
        self.summaryTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let due = await self.summaryScheduler.runDue()
                if !due.isEmpty {
                    await self.summarizeChatMemory()
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func summarizeChatMemory() async {
        let recent = self.messages.suffix(20)
        guard !recent.isEmpty else { return }
        let summary = recent
            .map { "[\($0.role.rawValue)] \($0.text)" }
            .joined(separator: "\n")

        let document = MemoryDocument(
            id: "summary-\(Int(Date().timeIntervalSince1970))",
            source: .systemNote,
            text: summary
        )
        await self.memoryIndex.upsert(document)
        self.latestSummary = summary
    }

    private func appendMessage(_ message: ChatMessage) {
        self.messages.append(message)
        self.persistMessages()
    }

    private func loadPersistedMessages() {
        guard let data = try? Data(contentsOf: self.messagesURL),
              let decoded = try? self.decoder.decode([ChatMessage].self, from: data)
        else {
            return
        }
        self.messages = decoded
    }

    private func persistMessages() {
        do {
            let data = try self.encoder.encode(self.messages)
            try data.write(to: self.messagesURL, options: [.atomic])
        } catch {
            self.statusText = "Warning: failed to save chat history."
        }
    }

    private func loadPersistedSettings() {
        guard let data = try? Data(contentsOf: self.settingsURL),
              let settings = try? self.decoder.decode(PersistedSettings.self, from: data)
        else {
            return
        }
        self.discordBotToken = settings.discordBotToken
        self.discordChannelID = settings.discordChannelID
        self.openAIAPIKey = settings.openAIAPIKey
        self.personality = settings.personality
    }

    private func persistSettings() throws {
        let settings = PersistedSettings(
            discordBotToken: self.discordBotToken,
            discordChannelID: self.discordChannelID,
            openAIAPIKey: self.openAIAPIKey,
            personality: self.personality
        )
        let data = try self.encoder.encode(settings)
        try data.write(to: self.settingsURL, options: [.atomic])
    }

    private func persistBootstrapFiles() throws {
        try FileManager.default.createDirectory(at: self.workspaceURL, withIntermediateDirectories: true)
        let soulURL = self.workspaceURL.appendingPathComponent("SOUL.md")
        let trimmed = self.personality.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if FileManager.default.fileExists(atPath: soulURL.path) {
                try FileManager.default.removeItem(at: soulURL)
            }
            return
        }
        try trimmed.write(to: soulURL, atomically: true, encoding: .utf8)
    }
}

private func normalized(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
