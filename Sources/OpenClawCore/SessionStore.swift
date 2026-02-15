import Foundation

public struct SessionRoute: Codable, Sendable, Equatable {
    public let channel: String
    public let accountID: String?
    public let peerID: String?

    public init(channel: String, accountID: String? = nil, peerID: String? = nil) {
        self.channel = channel
        self.accountID = accountID
        self.peerID = peerID
    }
}

public struct SessionRecord: Codable, Sendable, Equatable {
    public let key: String
    public var agentID: String
    public var updatedAtMs: Int
    public var lastRoute: SessionRoute?

    public init(key: String, agentID: String, updatedAtMs: Int, lastRoute: SessionRoute? = nil) {
        self.key = key
        self.agentID = agentID
        self.updatedAtMs = updatedAtMs
        self.lastRoute = lastRoute
    }
}

public struct SessionRoutingContext: Sendable, Equatable {
    public let channel: String
    public let accountID: String?
    public let peerID: String?

    public init(channel: String, accountID: String? = nil, peerID: String? = nil) {
        self.channel = channel
        self.accountID = accountID
        self.peerID = peerID
    }
}

public enum SessionKeyResolver {
    public static func derive(context: SessionRoutingContext, config: OpenClawConfig) -> String {
        let cleanChannel = sanitize(context.channel)
        let account = config.routing.includeAccountID ? sanitizeOptional(context.accountID) : nil
        let peer = config.routing.includePeerID ? sanitizeOptional(context.peerID) : nil

        let parts = [cleanChannel, account, peer].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return sanitize(config.routing.defaultSessionKey)
        }
        return parts.joined(separator: ":")
    }

    public static func resolve(explicit: String?, context: SessionRoutingContext?, config: OpenClawConfig) -> String {
        if let explicit {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return sanitize(trimmed)
            }
        }
        if let context {
            return derive(context: context, config: config)
        }
        return sanitize(config.routing.defaultSessionKey)
    }

    private static func sanitizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = sanitize(value)
        return clean.isEmpty ? nil : clean
    }

    private static func sanitize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}

public actor SessionStore {
    private let fileURL: URL
    private var records: [String: SessionRecord] = [:]

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws {
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
            self.records = [:]
            return
        }
        let data = try Data(contentsOf: self.fileURL)
        self.records = try JSONDecoder().decode([String: SessionRecord].self, from: data)
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(self.records)
        try data.write(to: self.fileURL, options: [.atomic])
    }

    public func upsert(_ record: SessionRecord) {
        self.records[record.key] = record
    }

    public func recordForKey(_ key: String) -> SessionRecord? {
        self.records[key]
    }

    public func allRecords() -> [SessionRecord] {
        self.records.values.sorted { $0.key < $1.key }
    }

    public func resolveOrCreate(
        sessionKey: String,
        defaultAgentID: String,
        route: SessionRoute?
    ) -> SessionRecord {
        if var existing = self.records[sessionKey] {
            existing.updatedAtMs = nowMs()
            if let route {
                existing.lastRoute = route
            }
            self.records[sessionKey] = existing
            return existing
        }

        let created = SessionRecord(
            key: sessionKey,
            agentID: defaultAgentID,
            updatedAtMs: nowMs(),
            lastRoute: route
        )
        self.records[sessionKey] = created
        return created
    }
}

private func nowMs() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}

