import Foundation
import OpenClawProtocol

public struct MemoryRecord: Codable, Sendable, Equatable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public actor MemoryIndex {
    private var records: [String: MemoryRecord] = [:]

    public init() {}

    public func upsert(_ record: MemoryRecord) {
        self.records[record.key] = record
    }

    public func get(key: String) -> MemoryRecord? {
        self.records[key]
    }
}

