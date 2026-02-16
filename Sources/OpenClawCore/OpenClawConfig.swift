import Foundation

/// Root configuration object for runtime, routing, channels, and models.
public struct OpenClawConfig: Codable, Sendable, Equatable {
    public var gateway: GatewayConfig
    public var agents: AgentsConfig
    public var channels: ChannelsConfig
    public var routing: RoutingConfig
    public var models: ModelsConfig

    /// Creates an OpenClaw runtime configuration.
    /// - Parameters:
    ///   - gateway: Gateway transport settings.
    ///   - agents: Agent workspace/default settings.
    ///   - channels: Channel adapter settings.
    ///   - routing: Session routing behavior.
    ///   - models: Model provider settings.
    public init(
        gateway: GatewayConfig = GatewayConfig(),
        agents: AgentsConfig = AgentsConfig(),
        channels: ChannelsConfig = ChannelsConfig(),
        routing: RoutingConfig = RoutingConfig(),
        models: ModelsConfig = ModelsConfig()
    ) {
        self.gateway = gateway
        self.agents = agents
        self.channels = channels
        self.routing = routing
        self.models = models
    }
}

/// Gateway client connection settings.
public struct GatewayConfig: Codable, Sendable, Equatable {
    public var host: String
    public var port: Int
    public var authMode: String

    /// Creates gateway settings.
    /// - Parameters:
    ///   - host: Gateway host name or IP.
    ///   - port: Gateway port.
    ///   - authMode: Gateway auth mode string.
    public init(host: String = "127.0.0.1", port: Int = 18789, authMode: String = "token") {
        self.host = host
        self.port = port
        self.authMode = authMode
    }
}

/// Agent runtime defaults and workspace location.
public struct AgentsConfig: Codable, Sendable, Equatable {
    public var defaultAgentID: String
    public var workspaceRoot: String

    /// Creates agent defaults.
    /// - Parameters:
    ///   - defaultAgentID: Default agent identifier.
    ///   - workspaceRoot: Workspace root path.
    public init(defaultAgentID: String = "main", workspaceRoot: String = "./workspace") {
        self.defaultAgentID = defaultAgentID
        self.workspaceRoot = workspaceRoot
    }
}

/// Session key routing behavior controls.
public struct RoutingConfig: Codable, Sendable, Equatable {
    public var defaultSessionKey: String
    public var includeAccountID: Bool
    public var includePeerID: Bool

    /// Creates routing settings.
    /// - Parameters:
    ///   - defaultSessionKey: Fallback session key.
    ///   - includeAccountID: Include account ID in derived key.
    ///   - includePeerID: Include peer ID in derived key.
    public init(
        defaultSessionKey: String = "main",
        includeAccountID: Bool = true,
        includePeerID: Bool = true
    ) {
        self.defaultSessionKey = defaultSessionKey
        self.includeAccountID = includeAccountID
        self.includePeerID = includePeerID
    }
}

/// Channel adapter related configuration.
public struct ChannelsConfig: Codable, Sendable, Equatable {
    public var discord: DiscordChannelConfig

    /// Creates channel config.
    /// - Parameter discord: Discord channel settings.
    public init(discord: DiscordChannelConfig = DiscordChannelConfig()) {
        self.discord = discord
    }
}

/// Discord adapter configuration.
public struct DiscordChannelConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var botToken: String?
    public var defaultChannelID: String?
    public var pollIntervalMs: Int

    /// Creates Discord channel settings.
    /// - Parameters:
    ///   - enabled: Enables Discord adapter startup.
    ///   - botToken: Bot token used for API auth.
    ///   - defaultChannelID: Default channel ID for polling/sends.
    ///   - pollIntervalMs: Poll interval in milliseconds.
    public init(
        enabled: Bool = false,
        botToken: String? = nil,
        defaultChannelID: String? = nil,
        pollIntervalMs: Int = 2_000
    ) {
        self.enabled = enabled
        self.botToken = botToken
        self.defaultChannelID = defaultChannelID
        self.pollIntervalMs = max(250, pollIntervalMs)
    }
}

/// Model routing and provider settings.
public struct ModelsConfig: Codable, Sendable, Equatable {
    public var defaultProviderID: String
    public var systemPrompt: String?
    public var openAI: OpenAIModelConfig
    public var foundation: FoundationModelConfig
    public var local: LocalModelConfig

    /// Creates model settings.
    /// - Parameters:
    ///   - defaultProviderID: Default provider ID when none is specified.
    ///   - systemPrompt: Optional system prompt prefix.
    ///   - openAI: OpenAI provider settings.
    ///   - foundation: Foundation Models settings.
    ///   - local: Local model settings.
    public init(
        defaultProviderID: String = "echo",
        systemPrompt: String? = nil,
        openAI: OpenAIModelConfig = OpenAIModelConfig(),
        foundation: FoundationModelConfig = FoundationModelConfig(),
        local: LocalModelConfig = LocalModelConfig()
    ) {
        self.defaultProviderID = defaultProviderID
        self.systemPrompt = systemPrompt
        self.openAI = openAI
        self.foundation = foundation
        self.local = local
    }
}

/// OpenAI provider-specific configuration.
public struct OpenAIModelConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var modelID: String
    public var apiKey: String?
    public var baseURL: String

    /// Creates OpenAI provider settings.
    /// - Parameters:
    ///   - enabled: Enables OpenAI provider routing.
    ///   - modelID: OpenAI model identifier.
    ///   - apiKey: OpenAI API key.
    ///   - baseURL: OpenAI-compatible API base URL.
    public init(
        enabled: Bool = false,
        modelID: String = "gpt-4.1-mini",
        apiKey: String? = nil,
        baseURL: String = "https://api.openai.com/v1"
    ) {
        self.enabled = enabled
        self.modelID = modelID
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
}

/// Apple Foundation Models provider settings.
public struct FoundationModelConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var preferredModelID: String?

    /// Creates Foundation Models settings.
    /// - Parameters:
    ///   - enabled: Enables provider selection.
    ///   - preferredModelID: Optional preferred model name.
    public init(enabled: Bool = false, preferredModelID: String? = nil) {
        self.enabled = enabled
        self.preferredModelID = preferredModelID
    }
}

/// Local inference runtime/provider settings.
public struct LocalModelConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var runtime: String
    public var modelPath: String?
    public var contextWindow: Int
    public var temperature: Double
    public var topP: Double
    public var maxTokens: Int

    /// Creates local model settings.
    /// - Parameters:
    ///   - enabled: Enables local provider selection.
    ///   - runtime: Runtime identifier (for example, `llmfarm`).
    ///   - modelPath: Model artifact path.
    ///   - contextWindow: Token context window size.
    ///   - temperature: Sampling temperature.
    ///   - topP: Top-p sampling value.
    ///   - maxTokens: Maximum generated token count.
    public init(
        enabled: Bool = false,
        runtime: String = "llmfarm",
        modelPath: String? = nil,
        contextWindow: Int = 4096,
        temperature: Double = 0.7,
        topP: Double = 0.95,
        maxTokens: Int = 512
    ) {
        self.enabled = enabled
        self.runtime = runtime
        self.modelPath = modelPath
        self.contextWindow = contextWindow
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = max(1, maxTokens)
    }
}

