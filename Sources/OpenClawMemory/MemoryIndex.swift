import Foundation
import OpenClawProtocol

public enum MemorySource: String, Codable, Sendable {
    case userMessage = "user_message"
    case toolResult = "tool_result"
    case systemNote = "system_note"
}

public struct MemoryDocument: Codable, Sendable, Equatable {
    public let id: String
    public let source: MemorySource
    public let text: String
    public let metadata: [String: String]

    public init(id: String, source: MemorySource, text: String, metadata: [String: String] = [:]) {
        self.id = id
        self.source = source
        self.text = text
        self.metadata = metadata
    }
}

public struct MemorySearchResult: Sendable, Equatable {
    public let id: String
    public let score: Double
    public let text: String
    public let source: MemorySource

    public init(id: String, score: Double, text: String, source: MemorySource) {
        self.id = id
        self.score = score
        self.text = text
        self.source = source
    }
}

public actor MemoryIndex {
    private var records: [String: MemoryDocument] = [:]

    public init() {}

    public func upsert(_ record: MemoryDocument) {
        self.records[record.id] = record
    }

    public func get(key: String) -> MemoryDocument? {
        self.records[key]
    }

    public func delete(key: String) {
        self.records.removeValue(forKey: key)
    }

    public func sync(_ documents: [MemoryDocument]) {
        for doc in documents {
            self.records[doc.id] = doc
        }
    }

    public func search(
        query: String,
        maxResults: Int = 8,
        minScore: Double = 0.0
    ) -> [MemorySearchResult] {
        let normalizedQuery = tokens(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let scored = self.records.values.map { doc -> MemorySearchResult in
            let docTokens = tokens(doc.text)
            let common = normalizedQuery.intersection(docTokens)
            let score = docTokens.isEmpty ? 0.0 : Double(common.count) / Double(docTokens.count)
            return MemorySearchResult(id: doc.id, score: score, text: doc.text, source: doc.source)
        }
        return scored
            .filter { $0.score >= minScore }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.id < rhs.id
                }
                return lhs.score > rhs.score
            }
            .prefix(maxResults)
            .map { $0 }
    }
}

private func tokens(_ text: String) -> Set<String> {
    let split = text
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
    return Set(split)
}

