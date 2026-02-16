import Foundation

public struct OpenClawConfig: Codable, Sendable, Equatable {
    public var gateway: GatewayConfig
    public var agents: AgentsConfig
    public var routing: RoutingConfig
    public var models: ModelsConfig

    public init(
        gateway: GatewayConfig = GatewayConfig(),
        agents: AgentsConfig = AgentsConfig(),
        routing: RoutingConfig = RoutingConfig(),
        models: ModelsConfig = ModelsConfig()
    ) {
        self.gateway = gateway
        self.agents = agents
        self.routing = routing
        self.models = models
    }
}

public struct GatewayConfig: Codable, Sendable, Equatable {
    public var host: String
    public var port: Int
    public var authMode: String

    public init(host: String = "127.0.0.1", port: Int = 18789, authMode: String = "token") {
        self.host = host
        self.port = port
        self.authMode = authMode
    }
}

public struct AgentsConfig: Codable, Sendable, Equatable {
    public var defaultAgentID: String
    public var workspaceRoot: String

    public init(defaultAgentID: String = "main", workspaceRoot: String = "./workspace") {
        self.defaultAgentID = defaultAgentID
        self.workspaceRoot = workspaceRoot
    }
}

public struct RoutingConfig: Codable, Sendable, Equatable {
    public var defaultSessionKey: String
    public var includeAccountID: Bool
    public var includePeerID: Bool

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

public struct ModelsConfig: Codable, Sendable, Equatable {
    public var defaultProviderID: String
    public var systemPrompt: String?
    public var openAI: OpenAIModelConfig
    public var foundation: FoundationModelConfig
    public var local: LocalModelConfig

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

public struct OpenAIModelConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var modelID: String
    public var apiKey: String?
    public var baseURL: String

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

public struct FoundationModelConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var preferredModelID: String?

    public init(enabled: Bool = false, preferredModelID: String? = nil) {
        self.enabled = enabled
        self.preferredModelID = preferredModelID
    }
}

public struct LocalModelConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var runtime: String
    public var modelPath: String?
    public var contextWindow: Int
    public var temperature: Double
    public var topP: Double
    public var maxTokens: Int

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

