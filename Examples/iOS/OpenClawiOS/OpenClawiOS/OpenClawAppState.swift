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

    /// User-selectable provider choices surfaced in deploy settings.
    enum DeployProvider: String, Codable, CaseIterable, Identifiable, Sendable {
        case echo
        case openAI
        case openAICompatible
        case anthropic
        case gemini
        case foundation
        case local

        var id: String { self.rawValue }

        var providerID: String {
            switch self {
            case .echo:
                return EchoModelProvider.defaultID
            case .openAI:
                return OpenAIModelProvider.providerID
            case .openAICompatible:
                return OpenAICompatibleModelProvider.providerID
            case .anthropic:
                return AnthropicModelProvider.providerID
            case .gemini:
                return GeminiModelProvider.providerID
            case .foundation:
                return FoundationModelsProvider.providerID
            case .local:
                return LocalModelProvider.providerID
            }
        }

        var displayName: String {
            switch self {
            case .echo:
                return "Echo (offline placeholder)"
            case .openAI:
                return "OpenAI"
            case .openAICompatible:
                return "OpenAI Compatible"
            case .anthropic:
                return "Anthropic"
            case .gemini:
                return "Google Gemini"
            case .foundation:
                return "Apple Foundation Models"
            case .local:
                return "Local (LLMFarm runtime)"
            }
        }

        var defaultModelID: String {
            switch self {
            case .echo:
                return "echo-1"
            case .openAI, .openAICompatible:
                return "gpt-4.1-mini"
            case .anthropic:
                return "claude-3-5-haiku-latest"
            case .gemini:
                return "gemini-2.0-flash"
            case .foundation:
                return "apple-foundation-default"
            case .local:
                return "local-default"
            }
        }
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

    /// Render model for a discovered skill row in the iOS app.
    struct SkillItem: Identifiable, Sendable, Equatable {
        let id: String
        let name: String
        let summary: String
        let source: String
        let primaryEnv: String
        let requiresExplicitInvocation: Bool
        let userInvocable: Bool
        let entrypoint: String?
    }

    /// Render model for channel health rows.
    struct ChannelHealthItem: Identifiable, Sendable, Equatable {
        let id: String
        let status: ChannelHealthStatus
        let consecutiveFailures: Int
        let lastError: String?
        let lastSuccessAt: Date?
        let lastFailureAt: Date?
    }

    /// Render model for route mapping previews.
    struct RouteMappingItem: Identifiable, Sendable, Equatable {
        let id: String
        let route: String
        let agentID: String
    }

    /// Persisted deployment settings loaded/saved between launches.
    struct PersistedSettings: Codable, Sendable {
        var discordBotToken: String
        var discordChannelID: String
        var openAIAPIKey: String
        var openAICompatibleAPIKey: String
        var openAICompatibleBaseURL: String
        var anthropicAPIKey: String
        var geminiAPIKey: String
        var selectedProvider: DeployProvider
        var selectedModelID: String
        var localRuntime: String
        var localModelPath: String
        var localFallbackModelPaths: String
        var localContextWindow: Int
        var localTemperature: Double
        var localTopP: Double
        var localTopK: Int
        var localMaxTokens: Int
        var localUseMetal: Bool
        var localStreamTokens: Bool
        var localAllowCancellation: Bool
        var localRequestTimeoutMs: Int
        var defaultAgentID: String
        var discordAgentID: String
        var webchatAgentID: String
        var personality: String

        init(
            discordBotToken: String,
            discordChannelID: String,
            openAIAPIKey: String,
            openAICompatibleAPIKey: String,
            openAICompatibleBaseURL: String,
            anthropicAPIKey: String,
            geminiAPIKey: String,
            selectedProvider: DeployProvider,
            selectedModelID: String,
            localRuntime: String,
            localModelPath: String,
            localFallbackModelPaths: String,
            localContextWindow: Int,
            localTemperature: Double,
            localTopP: Double,
            localTopK: Int,
            localMaxTokens: Int,
            localUseMetal: Bool,
            localStreamTokens: Bool,
            localAllowCancellation: Bool,
            localRequestTimeoutMs: Int,
            defaultAgentID: String,
            discordAgentID: String,
            webchatAgentID: String,
            personality: String
        ) {
            self.discordBotToken = discordBotToken
            self.discordChannelID = discordChannelID
            self.openAIAPIKey = openAIAPIKey
            self.openAICompatibleAPIKey = openAICompatibleAPIKey
            self.openAICompatibleBaseURL = openAICompatibleBaseURL
            self.anthropicAPIKey = anthropicAPIKey
            self.geminiAPIKey = geminiAPIKey
            self.selectedProvider = selectedProvider
            self.selectedModelID = selectedModelID
            self.localRuntime = localRuntime
            self.localModelPath = localModelPath
            self.localFallbackModelPaths = localFallbackModelPaths
            self.localContextWindow = localContextWindow
            self.localTemperature = localTemperature
            self.localTopP = localTopP
            self.localTopK = localTopK
            self.localMaxTokens = localMaxTokens
            self.localUseMetal = localUseMetal
            self.localStreamTokens = localStreamTokens
            self.localAllowCancellation = localAllowCancellation
            self.localRequestTimeoutMs = localRequestTimeoutMs
            self.defaultAgentID = defaultAgentID
            self.discordAgentID = discordAgentID
            self.webchatAgentID = webchatAgentID
            self.personality = personality
        }

        private enum CodingKeys: String, CodingKey {
            case discordBotToken
            case discordChannelID
            case openAIAPIKey
            case openAICompatibleAPIKey
            case openAICompatibleBaseURL
            case anthropicAPIKey
            case geminiAPIKey
            case selectedProvider
            case selectedModelID
            case localRuntime
            case localModelPath
            case localFallbackModelPaths
            case localContextWindow
            case localTemperature
            case localTopP
            case localTopK
            case localMaxTokens
            case localUseMetal
            case localStreamTokens
            case localAllowCancellation
            case localRequestTimeoutMs
            case defaultAgentID
            case discordAgentID
            case webchatAgentID
            case personality
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.discordBotToken = try container.decodeIfPresent(String.self, forKey: .discordBotToken) ?? ""
            self.discordChannelID = try container.decodeIfPresent(String.self, forKey: .discordChannelID) ?? ""
            self.openAIAPIKey = try container.decodeIfPresent(String.self, forKey: .openAIAPIKey) ?? ""
            self.openAICompatibleAPIKey = try container.decodeIfPresent(String.self, forKey: .openAICompatibleAPIKey) ?? ""
            self.openAICompatibleBaseURL = try container.decodeIfPresent(String.self, forKey: .openAICompatibleBaseURL) ?? "https://api.openai.com/v1"
            self.anthropicAPIKey = try container.decodeIfPresent(String.self, forKey: .anthropicAPIKey) ?? ""
            self.geminiAPIKey = try container.decodeIfPresent(String.self, forKey: .geminiAPIKey) ?? ""
            self.selectedProvider = try container.decodeIfPresent(DeployProvider.self, forKey: .selectedProvider) ?? .openAI
            self.selectedModelID = try container.decodeIfPresent(String.self, forKey: .selectedModelID) ?? self.selectedProvider.defaultModelID
            self.localRuntime = try container.decodeIfPresent(String.self, forKey: .localRuntime) ?? "llmfarm"
            self.localModelPath = try container.decodeIfPresent(String.self, forKey: .localModelPath) ?? ""
            self.localFallbackModelPaths = try container.decodeIfPresent(String.self, forKey: .localFallbackModelPaths) ?? ""
            self.localContextWindow = max(256, try container.decodeIfPresent(Int.self, forKey: .localContextWindow) ?? 4096)
            self.localTemperature = try container.decodeIfPresent(Double.self, forKey: .localTemperature) ?? 0.7
            self.localTopP = try container.decodeIfPresent(Double.self, forKey: .localTopP) ?? 0.95
            self.localTopK = max(1, try container.decodeIfPresent(Int.self, forKey: .localTopK) ?? 40)
            self.localMaxTokens = max(1, try container.decodeIfPresent(Int.self, forKey: .localMaxTokens) ?? 512)
            self.localUseMetal = try container.decodeIfPresent(Bool.self, forKey: .localUseMetal) ?? true
            self.localStreamTokens = try container.decodeIfPresent(Bool.self, forKey: .localStreamTokens) ?? true
            self.localAllowCancellation = try container.decodeIfPresent(Bool.self, forKey: .localAllowCancellation) ?? true
            self.localRequestTimeoutMs = max(1, try container.decodeIfPresent(Int.self, forKey: .localRequestTimeoutMs) ?? 60_000)
            self.defaultAgentID = try container.decodeIfPresent(String.self, forKey: .defaultAgentID) ?? "main"
            self.discordAgentID = try container.decodeIfPresent(String.self, forKey: .discordAgentID) ?? ""
            self.webchatAgentID = try container.decodeIfPresent(String.self, forKey: .webchatAgentID) ?? ""
            self.personality = try container.decodeIfPresent(String.self, forKey: .personality) ?? ""
        }
    }

    @Published var discordBotToken: String = ""
    @Published var discordChannelID: String = ""
    @Published var openAIAPIKey: String = ""
    @Published var openAICompatibleAPIKey: String = ""
    @Published var openAICompatibleBaseURL: String = "https://api.openai.com/v1"
    @Published var anthropicAPIKey: String = ""
    @Published var geminiAPIKey: String = ""
    @Published var selectedProvider: DeployProvider = .openAI
    @Published var selectedModelID: String = DeployProvider.openAI.defaultModelID
    @Published var localRuntime: String = "llmfarm"
    @Published var localModelPath: String = ""
    @Published var localFallbackModelPaths: String = ""
    @Published var localContextWindow: Int = 4096
    @Published var localTemperature: Double = 0.7
    @Published var localTopP: Double = 0.95
    @Published var localTopK: Int = 40
    @Published var localMaxTokens: Int = 512
    @Published var localUseMetal: Bool = true
    @Published var localStreamTokens: Bool = true
    @Published var localAllowCancellation: Bool = true
    @Published var localRequestTimeoutMs: Int = 60_000
    @Published var defaultAgentID: String = "main"
    @Published var discordAgentID: String = ""
    @Published var webchatAgentID: String = ""
    @Published var personality: String = ""
    @Published var pendingMessage: String = ""

    @Published private(set) var deploymentState: DeploymentState = .stopped
    @Published private(set) var statusText: String = "Not deployed"
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var latestSummary: String = ""
    @Published private(set) var skillItems: [SkillItem] = []
    @Published private(set) var channelHealthItems: [ChannelHealthItem] = []
    @Published private(set) var diagnosticEvents: [RuntimeDiagnosticEvent] = []
    @Published private(set) var usageSnapshot: RuntimeUsageSnapshot?
    @Published private(set) var activeRetryPolicy: ChannelSendRetryPolicy = ChannelSendRetryPolicy()

    /// Returns whether runtime deployment is actively running.
    var isDeployed: Bool {
        self.deploymentState == .running
    }

    /// All available provider selections rendered by deploy UI.
    var availableProviders: [DeployProvider] {
        DeployProvider.allCases
    }

    /// Route mapping preview used by Channels tab.
    var routeMappings: [RouteMappingItem] {
        let defaultID = normalized(self.defaultAgentID) ?? "main"
        var rows: [RouteMappingItem] = [
            RouteMappingItem(id: "default", route: "default", agentID: defaultID),
        ]
        if let discordAgentID = normalized(self.discordAgentID) {
            rows.append(
                RouteMappingItem(
                    id: ChannelID.discord.rawValue,
                    route: AgentsConfig.routeKey(channel: ChannelID.discord.rawValue),
                    agentID: discordAgentID
                )
            )
        }
        if let webchatAgentID = normalized(self.webchatAgentID) {
            rows.append(
                RouteMappingItem(
                    id: ChannelID.webchat.rawValue,
                    route: AgentsConfig.routeKey(channel: ChannelID.webchat.rawValue),
                    agentID: webchatAgentID
                )
            )
        }
        return rows
    }

    /// Most recent skill invocation summary derived from diagnostics events.
    var latestSkillInvocationSummary: String {
        guard let event = self.diagnosticEvents.reversed().first(where: {
            $0.subsystem == "channel" && $0.name == "skill.invoked"
        }) else {
            return "No skill invocation observed in this session yet."
        }
        let skillName = event.metadata["skillName"] ?? "unknown"
        let durationMs = event.metadata["durationMs"] ?? "n/a"
        let executor = event.metadata["executorID"] ?? "unknown"
        return "\(skillName) (\(durationMs) ms via \(executor))"
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
    private let conversationMemoryURL: URL
    private let sharedConversationSessionKey = "shared"

    private var webchatAdapter: InMemoryChannelAdapter?
    private var discordAdapter: DiscordChannelAdapter?
    private var channelRegistry: ChannelRegistry?
    private var replyEngine: AutoReplyEngine?
    private var conversationMemoryStore: ConversationMemoryStore?
    private var diagnosticsPipeline: RuntimeDiagnosticsPipeline?
    private var summaryTask: Task<Void, Never>?
    private var observabilityTask: Task<Void, Never>?

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
        self.conversationMemoryURL = self.stateRoot.appendingPathComponent("conversation-memory.json")

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
            try self.syncProjectSkillsIntoWorkspace()

            let discordConfig = DiscordChannelConfig(
                enabled: !self.discordBotToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !self.discordChannelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                botToken: normalized(self.discordBotToken),
                defaultChannelID: normalized(self.discordChannelID),
                pollIntervalMs: 2_000,
                mentionOnly: true
            )
            let modelsConfig = try self.makeModelsConfig()
            let agentsConfig = self.makeAgentsConfig()

            let config = OpenClawConfig(
                agents: agentsConfig,
                channels: ChannelsConfig(discord: discordConfig),
                routing: RoutingConfig(
                    defaultSessionKey: self.sharedConversationSessionKey,
                    includeChannelID: false,
                    includeAccountID: false,
                    includePeerID: false
                ),
                models: modelsConfig
            )

            try await self.sdk.saveConfig(config, to: self.configURL)
            try self.persistSettings()

            let sessionStore = SessionStore(fileURL: self.sessionsURL)
            try await sessionStore.load()
            let conversationMemoryStore = ConversationMemoryStore(fileURL: self.conversationMemoryURL)
            try await conversationMemoryStore.load()

            let channelRegistry = ChannelRegistry()
            let webchat = InMemoryChannelAdapter(id: .webchat)
            await channelRegistry.register(webchat)
            try await webchat.start()

            let diagnosticsPipeline = self.sdk.makeDiagnosticsPipeline(eventLimit: 600)
            let diagnosticsSink = await diagnosticsPipeline.sink()
            let runtime = EmbeddedAgentRuntime(diagnosticsSink: diagnosticsSink)
            try await self.registerSelectedModelProvider(on: runtime, using: config.models)
            let replyEngine = AutoReplyEngine(
                config: config,
                sessionStore: sessionStore,
                channelRegistry: channelRegistry,
                runtime: runtime,
                conversationMemoryStore: conversationMemoryStore,
                diagnosticsSink: diagnosticsSink
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
            self.channelRegistry = channelRegistry
            self.replyEngine = replyEngine
            self.conversationMemoryStore = conversationMemoryStore
            self.diagnosticsPipeline = diagnosticsPipeline

            await self.summaryScheduler.addOrUpdate(
                CronJob(
                    id: "chat-summary",
                    intervalSeconds: 60,
                    payload: "summary",
                    nextRunAt: Date().addingTimeInterval(60)
                )
            )
            self.startSummaryLoop()
            self.startObservabilityLoop()
            await self.refreshObservabilityState()

            self.deploymentState = .running
            self.statusText = self.discordAdapter == nil
                ? "Deployment running (local chat only, provider: \(self.selectedProvider.displayName))."
                : "Deployment running (Discord + local chat, provider: \(self.selectedProvider.displayName))."
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
        self.observabilityTask?.cancel()
        self.observabilityTask = nil

        if let discordAdapter {
            await discordAdapter.stop()
        }
        if let webchatAdapter {
            await webchatAdapter.stop()
        }

        self.discordAdapter = nil
        self.webchatAdapter = nil
        self.channelRegistry = nil
        self.replyEngine = nil
        self.conversationMemoryStore = nil
        self.diagnosticsPipeline = nil
        self.skillItems = []
        self.channelHealthItems = []
        self.diagnosticEvents = []
        self.usageSnapshot = nil
        self.activeRetryPolicy = ChannelSendRetryPolicy()
        self.deploymentState = .stopped
        self.statusText = "Deployment stopped."
    }

    /// Builds model config from current deploy-provider selections.
    private func makeAgentsConfig() -> AgentsConfig {
        let resolvedDefaultAgentID = normalized(self.defaultAgentID) ?? "main"
        var routeAgentMap: [String: String] = [:]

        if let discordAgentID = normalized(self.discordAgentID) {
            routeAgentMap[AgentsConfig.routeKey(channel: ChannelID.discord.rawValue)] = discordAgentID
        }
        if let webchatAgentID = normalized(self.webchatAgentID) {
            routeAgentMap[AgentsConfig.routeKey(channel: ChannelID.webchat.rawValue)] = webchatAgentID
        }

        var agentIDs: Set<String> = [resolvedDefaultAgentID]
        if let discordAgentID = normalized(self.discordAgentID) {
            agentIDs.insert(discordAgentID)
        }
        if let webchatAgentID = normalized(self.webchatAgentID) {
            agentIDs.insert(webchatAgentID)
        }

        return AgentsConfig(
            defaultAgentID: resolvedDefaultAgentID,
            workspaceRoot: self.workspaceURL.path,
            agentIDs: agentIDs.sorted(),
            routeAgentMap: routeAgentMap
        )
    }

    /// Builds model config from current deploy-provider selections.
    private func makeModelsConfig() throws -> ModelsConfig {
        let selectedModelID = normalized(self.selectedModelID) ?? self.selectedProvider.defaultModelID

        switch self.selectedProvider {
        case .echo:
            return ModelsConfig(
                defaultProviderID: EchoModelProvider.defaultID
            )
        case .openAI:
            guard let apiKey = normalized(self.openAIAPIKey) else {
                throw OpenClawCoreError.invalidConfiguration("OpenAI API key is required for OpenAI provider")
            }
            return ModelsConfig(
                defaultProviderID: OpenAIModelProvider.providerID,
                openAI: OpenAIModelConfig(
                    enabled: true,
                    modelID: selectedModelID,
                    apiKey: apiKey
                )
            )
        case .openAICompatible:
            guard let apiKey = normalized(self.openAICompatibleAPIKey) else {
                throw OpenClawCoreError.invalidConfiguration("API key is required for OpenAI-compatible provider")
            }
            return ModelsConfig(
                defaultProviderID: OpenAICompatibleModelProvider.providerID,
                openAICompatible: OpenAICompatibleModelConfig(
                    enabled: true,
                    modelID: selectedModelID,
                    apiKey: apiKey,
                    baseURL: normalized(self.openAICompatibleBaseURL) ?? "https://api.openai.com/v1"
                )
            )
        case .anthropic:
            guard let apiKey = normalized(self.anthropicAPIKey) else {
                throw OpenClawCoreError.invalidConfiguration("Anthropic API key is required for Anthropic provider")
            }
            return ModelsConfig(
                defaultProviderID: AnthropicModelProvider.providerID,
                anthropic: AnthropicModelConfig(
                    enabled: true,
                    modelID: selectedModelID,
                    apiKey: apiKey
                )
            )
        case .gemini:
            guard let apiKey = normalized(self.geminiAPIKey) else {
                throw OpenClawCoreError.invalidConfiguration("Gemini API key is required for Gemini provider")
            }
            return ModelsConfig(
                defaultProviderID: GeminiModelProvider.providerID,
                gemini: GeminiModelConfig(
                    enabled: true,
                    modelID: selectedModelID,
                    apiKey: apiKey
                )
            )
        case .foundation:
            return ModelsConfig(
                defaultProviderID: FoundationModelsProvider.providerID,
                foundation: FoundationModelConfig(enabled: true, preferredModelID: selectedModelID)
            )
        case .local:
            let fallbackPaths = self.localFallbackModelPaths
                .split(whereSeparator: { $0 == "," || $0.isNewline })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let configuredModelPath = normalized(self.localModelPath)
            return ModelsConfig(
                defaultProviderID: LocalModelProvider.providerID,
                local: LocalModelConfig(
                    enabled: true,
                    runtime: normalized(self.localRuntime) ?? "llmfarm",
                    modelPath: configuredModelPath,
                    contextWindow: max(256, self.localContextWindow),
                    temperature: self.localTemperature,
                    topP: self.localTopP,
                    topK: max(1, self.localTopK),
                    useMetal: self.localUseMetal,
                    streamTokens: self.localStreamTokens,
                    allowCancellation: self.localAllowCancellation,
                    requestTimeoutMs: max(1, self.localRequestTimeoutMs),
                    fallbackModelPaths: fallbackPaths,
                    runtimeOptions: [:],
                    maxTokens: max(1, self.localMaxTokens)
                )
            )
        }
    }

    /// Registers and activates currently selected model provider on runtime.
    private func registerSelectedModelProvider(
        on runtime: EmbeddedAgentRuntime,
        using models: ModelsConfig
    ) async throws {
        switch self.selectedProvider {
        case .echo:
            try await runtime.setDefaultModelProviderID(EchoModelProvider.defaultID)
        case .openAI:
            await runtime.registerModelProvider(OpenAIModelProvider(configuration: models.openAI))
            try await runtime.setDefaultModelProviderID(OpenAIModelProvider.providerID)
        case .openAICompatible:
            await runtime.registerModelProvider(OpenAICompatibleModelProvider(configuration: models.openAICompatible))
            try await runtime.setDefaultModelProviderID(OpenAICompatibleModelProvider.providerID)
        case .anthropic:
            await runtime.registerModelProvider(AnthropicModelProvider(configuration: models.anthropic))
            try await runtime.setDefaultModelProviderID(AnthropicModelProvider.providerID)
        case .gemini:
            await runtime.registerModelProvider(GeminiModelProvider(configuration: models.gemini))
            try await runtime.setDefaultModelProviderID(GeminiModelProvider.providerID)
        case .foundation:
            await runtime.registerModelProvider(FoundationModelsProvider())
            try await runtime.setDefaultModelProviderID(FoundationModelsProvider.providerID)
        case .local:
            await runtime.registerModelProvider(
                LocalModelProvider(
                    configuration: models.local,
                    engine: StubLocalModelEngine()
                )
            )
            try await runtime.setDefaultModelProviderID(LocalModelProvider.providerID)
        }
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
        await self.refreshObservabilityState()
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

    /// Forces an immediate refresh of diagnostics, channels, and discovered skills.
    func refreshObservabilityNow() async {
        await self.refreshObservabilityState()
    }

    /// Starts background observability polling loop.
    private func startObservabilityLoop() {
        self.observabilityTask?.cancel()
        self.observabilityTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshObservabilityState()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    /// Updates diagnostics snapshots, channel health, and skill inventory.
    private func refreshObservabilityState() async {
        if let diagnosticsPipeline = self.diagnosticsPipeline {
            self.usageSnapshot = await diagnosticsPipeline.usageSnapshot()
            self.diagnosticEvents = await diagnosticsPipeline.recentEvents(limit: 120)
        }

        if let channelRegistry = self.channelRegistry {
            let policy = await channelRegistry.retryPolicy()
            let snapshots = await channelRegistry.allHealthSnapshots()
            self.activeRetryPolicy = policy
            self.channelHealthItems = snapshots.map { snapshot in
                ChannelHealthItem(
                    id: snapshot.channelID.rawValue,
                    status: snapshot.status,
                    consecutiveFailures: snapshot.consecutiveFailures,
                    lastError: snapshot.lastError,
                    lastSuccessAt: snapshot.lastSuccessAt,
                    lastFailureAt: snapshot.lastFailureAt
                )
            }
        }

        let registry = SkillRegistry(workspaceRoot: self.workspaceURL)
        if let skills = try? await registry.loadSkills() {
            self.skillItems = skills.map { skill in
                SkillItem(
                    id: skill.name,
                    name: skill.name,
                    summary: skill.description.isEmpty ? "No description" : skill.description,
                    source: skill.source.rawValue,
                    primaryEnv: skill.metadata.primaryEnv ?? "unknown",
                    requiresExplicitInvocation: skill.invocation.requiresExplicitInvocation,
                    userInvocable: skill.invocation.userInvocable,
                    entrypoint: Self.skillEntrypointHint(for: skill)
                )
            }
        }
    }

    /// Resolves preferred entrypoint hint from skill frontmatter keys.
    private static func skillEntrypointHint(for skill: SkillDefinition) -> String? {
        for key in ["entrypoint", "script", "run"] {
            if let value = skill.frontmatter[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
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
        if let store = self.conversationMemoryStore {
            await store.appendAssistantTurn(
                sessionKey: self.sharedConversationSessionKey,
                channel: "webchat",
                accountID: nil,
                peerID: "summary",
                text: "Summary snapshot:\n\(summary)"
            )
            try? await store.save()
        }
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
        self.openAICompatibleAPIKey = settings.openAICompatibleAPIKey
        self.openAICompatibleBaseURL = settings.openAICompatibleBaseURL
        self.anthropicAPIKey = settings.anthropicAPIKey
        self.geminiAPIKey = settings.geminiAPIKey
        self.selectedProvider = settings.selectedProvider
        self.selectedModelID = settings.selectedModelID
        self.localRuntime = settings.localRuntime
        self.localModelPath = settings.localModelPath
        self.localFallbackModelPaths = settings.localFallbackModelPaths
        self.localContextWindow = settings.localContextWindow
        self.localTemperature = settings.localTemperature
        self.localTopP = settings.localTopP
        self.localTopK = settings.localTopK
        self.localMaxTokens = settings.localMaxTokens
        self.localUseMetal = settings.localUseMetal
        self.localStreamTokens = settings.localStreamTokens
        self.localAllowCancellation = settings.localAllowCancellation
        self.localRequestTimeoutMs = settings.localRequestTimeoutMs
        self.defaultAgentID = settings.defaultAgentID
        self.discordAgentID = settings.discordAgentID
        self.webchatAgentID = settings.webchatAgentID
        self.personality = settings.personality
        if self.selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.selectedModelID = self.selectedProvider.defaultModelID
        }
        if self.defaultAgentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.defaultAgentID = "main"
        }
    }

    /// Persists deployment settings to local storage.
    private func persistSettings() throws {
        let settings = PersistedSettings(
            discordBotToken: self.discordBotToken,
            discordChannelID: self.discordChannelID,
            openAIAPIKey: self.openAIAPIKey,
            openAICompatibleAPIKey: self.openAICompatibleAPIKey,
            openAICompatibleBaseURL: self.openAICompatibleBaseURL,
            anthropicAPIKey: self.anthropicAPIKey,
            geminiAPIKey: self.geminiAPIKey,
            selectedProvider: self.selectedProvider,
            selectedModelID: self.selectedModelID,
            localRuntime: self.localRuntime,
            localModelPath: self.localModelPath,
            localFallbackModelPaths: self.localFallbackModelPaths,
            localContextWindow: self.localContextWindow,
            localTemperature: self.localTemperature,
            localTopP: self.localTopP,
            localTopK: self.localTopK,
            localMaxTokens: self.localMaxTokens,
            localUseMetal: self.localUseMetal,
            localStreamTokens: self.localStreamTokens,
            localAllowCancellation: self.localAllowCancellation,
            localRequestTimeoutMs: self.localRequestTimeoutMs,
            defaultAgentID: self.defaultAgentID,
            discordAgentID: self.discordAgentID,
            webchatAgentID: self.webchatAgentID,
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

    /// Syncs repository skill folders into the iOS sandbox workspace.
    private func syncProjectSkillsIntoWorkspace() throws {
        guard let sourceSkillsRoot = Self.resolveProjectSkillsRoot(),
              FileManager.default.fileExists(atPath: sourceSkillsRoot.path)
        else {
            return
        }

        let destinationSkillsRoot = self.workspaceURL.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationSkillsRoot, withIntermediateDirectories: true)
        let sourceEntries = try FileManager.default.contentsOfDirectory(
            at: sourceSkillsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for sourceEntry in sourceEntries {
            guard (try? sourceEntry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let destinationEntry = destinationSkillsRoot.appendingPathComponent(sourceEntry.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationEntry.path) {
                try FileManager.default.removeItem(at: destinationEntry)
            }
            try FileManager.default.copyItem(at: sourceEntry, to: destinationEntry)
        }
    }

    /// Resolves the repository-level `skills` directory when running from source.
    private static func resolveProjectSkillsRoot() -> URL? {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = current.appendingPathComponent("skills", isDirectory: true)
            let weatherMarker = candidate
                .appendingPathComponent("weather", isDirectory: true)
                .appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: weatherMarker.path) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return nil
    }
}

/// Returns a trimmed value or `nil` when empty.
private func normalized(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
