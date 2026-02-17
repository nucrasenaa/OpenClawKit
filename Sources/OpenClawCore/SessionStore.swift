import Foundation

/// Route metadata associated with a session.
public struct SessionRoute: Codable, Sendable, Equatable {
    /// Channel identifier.
    public let channel: String
    /// Optional account identifier.
    public let accountID: String?
    /// Optional peer/channel identifier.
    public let peerID: String?

    /// Creates session route metadata.
    /// - Parameters:
    ///   - channel: Channel identifier.
    ///   - accountID: Optional account identifier.
    ///   - peerID: Optional peer identifier.
    public init(channel: String, accountID: String? = nil, peerID: String? = nil) {
        self.channel = channel
        self.accountID = accountID
        self.peerID = peerID
    }
}

/// Persisted session record.
public struct SessionRecord: Codable, Sendable, Equatable {
    /// Session key.
    public let key: String
    /// Agent identifier bound to this session.
    public var agentID: String
    /// Last updated timestamp in milliseconds since epoch.
    public var updatedAtMs: Int
    /// Last observed route metadata.
    public var lastRoute: SessionRoute?

    /// Creates a session record.
    /// - Parameters:
    ///   - key: Session key.
    ///   - agentID: Bound agent identifier.
    ///   - updatedAtMs: Last update timestamp in milliseconds.
    ///   - lastRoute: Optional route metadata.
    public init(key: String, agentID: String, updatedAtMs: Int, lastRoute: SessionRoute? = nil) {
        self.key = key
        self.agentID = agentID
        self.updatedAtMs = updatedAtMs
        self.lastRoute = lastRoute
    }
}

/// Inputs used for deriving session keys.
public struct SessionRoutingContext: Sendable, Equatable {
    /// Channel identifier.
    public let channel: String
    /// Optional account identifier.
    public let accountID: String?
    /// Optional peer identifier.
    public let peerID: String?

    /// Creates routing context.
    /// - Parameters:
    ///   - channel: Channel identifier.
    ///   - accountID: Optional account identifier.
    ///   - peerID: Optional peer identifier.
    public init(channel: String, accountID: String? = nil, peerID: String? = nil) {
        self.channel = channel
        self.accountID = accountID
        self.peerID = peerID
    }
}

/// Session key derivation and resolution helpers.
public enum SessionKeyResolver {
    /// Derives a session key from routing context and config flags.
    /// - Parameters:
    ///   - context: Routing context.
    ///   - config: Runtime configuration.
    /// - Returns: Sanitized derived session key.
    public static func derive(context: SessionRoutingContext, config: OpenClawConfig) -> String {
        let cleanChannel = config.routing.includeChannelID ? sanitizeOptional(context.channel) : nil
        let account = config.routing.includeAccountID ? sanitizeOptional(context.accountID) : nil
        let peer = config.routing.includePeerID ? sanitizeOptional(context.peerID) : nil

        let parts = [cleanChannel, account, peer].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return sanitize(config.routing.defaultSessionKey)
        }
        return parts.joined(separator: ":")
    }

    /// Resolves effective session key from explicit value or context fallback.
    /// - Parameters:
    ///   - explicit: Explicit key if provided.
    ///   - context: Optional routing context.
    ///   - config: Runtime configuration.
    /// - Returns: Sanitized resolved session key.
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

/// Actor-backed persisted session store.
public actor SessionStore {
    private let fileURL: URL
    private var records: [String: SessionRecord] = [:]

    /// Creates a session store.
    /// - Parameter fileURL: Session store JSON file URL.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Loads session records from disk.
    public func load() throws {
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
            self.records = [:]
            return
        }
        let data = try Data(contentsOf: self.fileURL)
        self.records = try JSONDecoder().decode([String: SessionRecord].self, from: data)
    }

    /// Saves current records to disk atomically.
    public func save() throws {
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(self.records)
        try data.write(to: self.fileURL, options: [.atomic])
    }

    /// Inserts or replaces a session record.
    /// - Parameter record: Session record.
    public func upsert(_ record: SessionRecord) {
        self.records[record.key] = record
    }

    /// Returns a session record by key.
    /// - Parameter key: Session key.
    /// - Returns: Matching record when present.
    public func recordForKey(_ key: String) -> SessionRecord? {
        self.records[key]
    }

    /// Returns all session records sorted by key.
    public func allRecords() -> [SessionRecord] {
        self.records.values.sorted { $0.key < $1.key }
    }

    /// Resolves an existing session or creates a new one.
    /// - Parameters:
    ///   - sessionKey: Session key.
    ///   - defaultAgentID: Default agent identifier for new sessions.
    ///   - route: Optional route metadata.
    /// - Returns: Existing or newly created session record.
    public func resolveOrCreate(
        sessionKey: String,
        defaultAgentID: String,
        route: SessionRoute?
    ) -> SessionRecord {
        if var existing = self.records[sessionKey] {
            existing.updatedAtMs = nowMs()
            existing.agentID = defaultAgentID
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

