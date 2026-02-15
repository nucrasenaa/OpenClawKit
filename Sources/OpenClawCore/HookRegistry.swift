import Foundation
import OpenClawProtocol

public enum HookName: String, Sendable {
    case beforeAgentStart = "before_agent_start"
    case afterToolCall = "after_tool_call"
    case gatewayStart = "gateway_start"
    case gatewayStop = "gateway_stop"
}

public struct HookContext: Sendable, Equatable {
    public let runID: String?
    public let sessionKey: String?
    public let metadata: [String: AnyCodable]

    public init(runID: String? = nil, sessionKey: String? = nil, metadata: [String: AnyCodable] = [:]) {
        self.runID = runID
        self.sessionKey = sessionKey
        self.metadata = metadata
    }
}

public struct HookResult: Sendable, Equatable {
    public let metadata: [String: AnyCodable]

    public init(metadata: [String: AnyCodable] = [:]) {
        self.metadata = metadata
    }
}

public typealias HookHandler = @Sendable (HookContext) async throws -> HookResult?

public actor HookRegistry {
    private var handlers: [HookName: [HookHandler]] = [:]

    public init() {}

    public func register(_ hook: HookName, handler: @escaping HookHandler) {
        var current = self.handlers[hook] ?? []
        current.append(handler)
        self.handlers[hook] = current
    }

    public func emit(_ hook: HookName, context: HookContext) async throws -> [HookResult] {
        let handlers = self.handlers[hook] ?? []
        var results: [HookResult] = []
        for handler in handlers {
            if let result = try await handler(context) {
                results.append(result)
            }
        }
        return results
    }
}

