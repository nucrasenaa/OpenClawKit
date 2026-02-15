import Foundation

public struct OpenClawConfig: Codable, Sendable, Equatable {
    public var gateway: GatewayConfig
    public var agents: AgentsConfig
    public var routing: RoutingConfig

    public init(
        gateway: GatewayConfig = GatewayConfig(),
        agents: AgentsConfig = AgentsConfig(),
        routing: RoutingConfig = RoutingConfig()
    ) {
        self.gateway = gateway
        self.agents = agents
        self.routing = routing
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

