import Foundation
import OpenClawKit
import Combine
import SwiftUI

/// Observable app state coordinating deployment and chat flows in the iOS example.
@MainActor
final class OpenClawAppState: ObservableObject {
    /// Deployment lifecycle states for the sample app.
    enum DeploymentState: String, Sendable {
        case stopped
        case starting
        case running
        case stopping
        case failed
    }

    /// Message role labels rendered by the sample chat timeline.
    enum MessageRole: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    /// Persisted chat message model used by local transcript storage.
    struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
        let id: UUID
        let role: MessageRole
        let text: String
        let createdAt: Date

        /// Creates a chat message.
        /// - Parameters:
        ///   - id: Stable message identifier.
        ///   - role: Message role label.
        ///   - text: Message text.
        ///   - createdAt: Creation timestamp.
        init(id: UUID = UUID(), role: MessageRole, text: String, createdAt: Date = Date()) {
            self.id = id
            self.role = role
            self.text = text
            self.createdAt = createdAt
        }
    }

    /// Persisted deployment settings loaded/saved between launches.
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

    /// Returns whether runtime deployment is actively running.
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

    /// Creates and initializes app state from persisted local storage.
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

    /// Starts runtime deployment using current credentials and settings.
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
                pollIntervalMs: 2_000,
                mentionOnly: true
            )
            let openAIEnabled = !self.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let config = OpenClawConfig(
                agents: AgentsConfig(defaultAgentID: "main", workspaceRoot: self.workspaceURL.path),
                channels: ChannelsConfig(discord: discordConfig),
                models: ModelsConfig(
                    defaultProviderID: openAIEnabled ? OpenAIModelProvider.providerID : EchoModelProvider.defaultID,
                    openAI: OpenAIModelConfig(
                        enabled: openAIEnabled,
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
            if openAIEnabled {
                await runtime.registerModelProvider(
                    OpenAIModelProvider(configuration: config.models.openAI)
                )
                try await runtime.setDefaultModelProviderID(OpenAIModelProvider.providerID)
            }
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

    /// Stops deployment and tears down adapter/runtime resources.
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

    /// Sends the currently drafted message if non-empty.
    func sendPendingMessage() async {
        let text = self.pendingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        self.pendingMessage = ""
        await self.sendMessage(text)
    }

    /// Sends a chat message through the active auto-reply engine.
    /// - Parameter text: User input message text.
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

    /// Starts background summary scheduler polling loop.
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

    /// Summarizes recent transcript entries into memory index state.
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

    /// Appends a message to timeline and persists transcript.
    /// - Parameter message: Message to append.
    private func appendMessage(_ message: ChatMessage) {
        self.messages.append(message)
        self.persistMessages()
    }

    /// Loads persisted transcript messages from disk.
    private func loadPersistedMessages() {
        guard let data = try? Data(contentsOf: self.messagesURL),
              let decoded = try? self.decoder.decode([ChatMessage].self, from: data)
        else {
            return
        }
        self.messages = decoded
    }

    /// Persists transcript messages to local storage.
    private func persistMessages() {
        do {
            let data = try self.encoder.encode(self.messages)
            try data.write(to: self.messagesURL, options: [.atomic])
        } catch {
            self.statusText = "Warning: failed to save chat history."
        }
    }

    /// Loads persisted deployment settings from disk.
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

    /// Persists deployment settings to local storage.
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

    /// Persists personality text as workspace bootstrap context.
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

/// Returns a trimmed value or `nil` when empty.
private func normalized(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
