import Foundation

public actor ConfigStore {
    private let fileURL: URL
    private let cacheTTLms: Int
    private var cached: (expiresAt: Date, value: OpenClawConfig)?

    public init(fileURL: URL, cacheTTLms: Int = 200) {
        self.fileURL = fileURL
        self.cacheTTLms = max(0, cacheTTLms)
    }

    public func load() throws -> OpenClawConfig {
        let data = try Data(contentsOf: self.fileURL)
        let config = try JSONDecoder().decode(OpenClawConfig.self, from: data)
        self.cached = nil
        return config
    }

    public func loadCached() throws -> OpenClawConfig {
        if let cached, cached.expiresAt > Date() {
            return cached.value
        }

        let loaded = try self.load()
        if self.cacheTTLms > 0 {
            let expiry = Date().addingTimeInterval(Double(self.cacheTTLms) / 1000.0)
            self.cached = (expiresAt: expiry, value: loaded)
        }
        return loaded
    }

    public func save(_ config: OpenClawConfig) throws {
        let data = try JSONEncoder().encode(config)
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: self.fileURL, options: [.atomic])
        self.cached = nil
    }

    public func clearCache() {
        self.cached = nil
    }
}

