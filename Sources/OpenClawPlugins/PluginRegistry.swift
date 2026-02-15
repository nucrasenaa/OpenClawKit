import Foundation
import OpenClawCore
import OpenClawProtocol

public protocol OpenClawPlugin: Sendable {
    var id: String { get }
    func register(api: PluginAPI) async throws
}

public actor PluginRegistry {
    private var pluginIDs: Set<String> = []
    private var toolNamesByPlugin: [String: Set<String>] = [:]
    private var hooks: [PluginHookName: [PluginHookHandler]] = [:]
    private var gatewayMethods: [String: PluginGatewayMethodHandler] = [:]
    private var services: [String: any PluginService] = [:]

    public init() {}

    public func load(plugin: any OpenClawPlugin) async throws {
        self.register(id: plugin.id)
        let api = PluginAPI(
            registerToolName: { [weak self] pluginID, toolName in
                await self?.registerToolName(pluginID: pluginID, toolName: toolName)
            },
            registerHook: { [weak self] hookName, handler in
                await self?.registerHook(hookName, handler: handler)
            },
            registerGatewayMethod: { [weak self] method, handler in
                await self?.registerGatewayMethod(method, handler: handler)
            },
            registerService: { [weak self] service in
                await self?.registerService(service)
            }
        )
        try await plugin.register(api: api)
    }

    public func register(id: String) {
        self.pluginIDs.insert(id)
    }

    public func contains(id: String) -> Bool {
        self.pluginIDs.contains(id)
    }

    public func allIDs() -> [String] {
        self.pluginIDs.sorted()
    }

    public func registerToolName(pluginID: String, toolName: String) {
        var current = self.toolNamesByPlugin[pluginID] ?? []
        current.insert(toolName)
        self.toolNamesByPlugin[pluginID] = current
    }

    public func toolNames(pluginID: String) -> [String] {
        Array(self.toolNamesByPlugin[pluginID] ?? []).sorted()
    }

    public func registerHook(_ hookName: PluginHookName, handler: @escaping PluginHookHandler) {
        var current = self.hooks[hookName] ?? []
        current.append(handler)
        self.hooks[hookName] = current
    }

    public func emitHook(
        _ hookName: PluginHookName,
        payload: PluginHookPayload
    ) async throws -> [PluginHookResult] {
        let handlers = self.hooks[hookName] ?? []
        var results: [PluginHookResult] = []
        for handler in handlers {
            if let result = try await handler(payload) {
                results.append(result)
            }
        }
        return results
    }

    public func registerGatewayMethod(
        _ method: String,
        handler: @escaping PluginGatewayMethodHandler
    ) {
        self.gatewayMethods[method] = handler
    }

    public func invokeGatewayMethod(
        _ method: String,
        params: [String: AnyCodable]
    ) async throws -> AnyCodable {
        guard let handler = self.gatewayMethods[method] else {
            throw OpenClawCoreError.unavailable("Plugin gateway method not found: \(method)")
        }
        return try await handler(params)
    }

    public func registerService(_ service: any PluginService) {
        self.services[service.id] = service
    }

    public func startServices() async throws {
        for service in self.services.values {
            try await service.start()
        }
    }

    public func stopServices() async {
        for service in self.services.values {
            await service.stop()
        }
    }
}

public enum PluginHookName: String, Sendable {
    case beforeAgentStart = "before_agent_start"
    case afterToolCall = "after_tool_call"
    case gatewayStart = "gateway_start"
    case gatewayStop = "gateway_stop"
}

public struct PluginHookPayload: Sendable, Equatable {
    public let runID: String?
    public let sessionKey: String?
    public let metadata: [String: AnyCodable]

    public init(runID: String? = nil, sessionKey: String? = nil, metadata: [String: AnyCodable] = [:]) {
        self.runID = runID
        self.sessionKey = sessionKey
        self.metadata = metadata
    }
}

public struct PluginHookResult: Sendable, Equatable {
    public let metadata: [String: AnyCodable]

    public init(metadata: [String: AnyCodable] = [:]) {
        self.metadata = metadata
    }
}

public typealias PluginHookHandler = @Sendable (PluginHookPayload) async throws -> PluginHookResult?
public typealias PluginGatewayMethodHandler = @Sendable ([String: AnyCodable]) async throws -> AnyCodable

public protocol PluginService: Sendable {
    var id: String { get }
    func start() async throws
    func stop() async
}

public struct PluginAPI: Sendable {
    private let registerToolNameFn: @Sendable (_ pluginID: String, _ toolName: String) async -> Void
    private let registerHookFn: @Sendable (_ hookName: PluginHookName, _ handler: @escaping PluginHookHandler) async -> Void
    private let registerGatewayMethodFn: @Sendable (_ method: String, _ handler: @escaping PluginGatewayMethodHandler) async -> Void
    private let registerServiceFn: @Sendable (_ service: any PluginService) async -> Void

    public init(
        registerToolName: @escaping @Sendable (_ pluginID: String, _ toolName: String) async -> Void,
        registerHook: @escaping @Sendable (_ hookName: PluginHookName, _ handler: @escaping PluginHookHandler) async -> Void,
        registerGatewayMethod: @escaping @Sendable (_ method: String, _ handler: @escaping PluginGatewayMethodHandler) async -> Void,
        registerService: @escaping @Sendable (_ service: any PluginService) async -> Void
    ) {
        self.registerToolNameFn = registerToolName
        self.registerHookFn = registerHook
        self.registerGatewayMethodFn = registerGatewayMethod
        self.registerServiceFn = registerService
    }

    public func registerToolName(pluginID: String, toolName: String) async {
        await self.registerToolNameFn(pluginID, toolName)
    }

    public func registerHook(_ hookName: PluginHookName, handler: @escaping PluginHookHandler) async {
        await self.registerHookFn(hookName, handler)
    }

    public func registerGatewayMethod(
        _ method: String,
        handler: @escaping PluginGatewayMethodHandler
    ) async {
        await self.registerGatewayMethodFn(method, handler)
    }

    public func registerService(_ service: any PluginService) async {
        await self.registerServiceFn(service)
    }
}

