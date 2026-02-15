import Foundation
import OpenClawAgents
import OpenClawProtocol

public protocol OpenClawPlugin: Sendable {
    var id: String { get }
    func register(in registry: PluginRegistry) async throws
}

public actor PluginRegistry {
    private var pluginIDs: Set<String> = []

    public init() {}

    public func register(id: String) {
        self.pluginIDs.insert(id)
    }

    public func contains(id: String) -> Bool {
        self.pluginIDs.contains(id)
    }

    public func allIDs() -> [String] {
        self.pluginIDs.sorted()
    }
}

