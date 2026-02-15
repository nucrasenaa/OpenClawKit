import Foundation
import OpenClawProtocol

public protocol AgentTool: Sendable {
    var name: String { get }
    func execute(arguments: [String: AnyCodable]) async throws -> AnyCodable
}

public struct AgentToolCall: Sendable, Equatable {
    public let name: String
    public let arguments: [String: AnyCodable]

    public init(name: String, arguments: [String: AnyCodable] = [:]) {
        self.name = name
        self.arguments = arguments
    }
}

public struct AgentToolResult: Sendable, Equatable {
    public let name: String
    public let value: AnyCodable

    public init(name: String, value: AnyCodable) {
        self.name = name
        self.value = value
    }
}

public actor AgentToolRegistry {
    private var tools: [String: any AgentTool] = [:]

    public init() {}

    public func register(_ tool: any AgentTool) {
        self.tools[tool.name] = tool
    }

    public func hasTool(named name: String) -> Bool {
        self.tools[name] != nil
    }

    public func execute(_ call: AgentToolCall) async throws -> AgentToolResult {
        guard let tool = self.tools[call.name] else {
            throw AgentRuntimeError.toolNotFound(call.name)
        }
        let value = try await tool.execute(arguments: call.arguments)
        return AgentToolResult(name: call.name, value: value)
    }
}

