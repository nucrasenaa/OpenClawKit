import Foundation
import OpenClawGateway
import OpenClawPlugins

public protocol ChannelAdapter: Sendable {
    var id: String { get }
    func start() async throws
    func stop() async
}

public actor ChannelRegistry {
    private var adapters: [String: any ChannelAdapter] = [:]

    public init() {}

    public func register(_ adapter: any ChannelAdapter) {
        self.adapters[adapter.id] = adapter
    }

    public func hasAdapter(id: String) -> Bool {
        self.adapters[id] != nil
    }

    public func adapterIDs() -> [String] {
        self.adapters.keys.sorted()
    }
}

