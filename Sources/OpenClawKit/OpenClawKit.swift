@_exported import OpenClawAgents
@_exported import OpenClawChannels
@_exported import OpenClawCore
@_exported import OpenClawGateway
@_exported import OpenClawMedia
@_exported import OpenClawMemory
@_exported import OpenClawModels
@_exported import OpenClawPlugins
@_exported import OpenClawProtocol
import Foundation

public struct OpenClawSDK: Sendable {
    public static let shared = OpenClawSDK()

    public let buildInfo: OpenClawBuildInfo

    public init(buildInfo: OpenClawBuildInfo = OpenClawBuildInfo(protocolVersion: GATEWAY_PROTOCOL_VERSION)) {
        self.buildInfo = buildInfo
    }

    public func loadConfig(from fileURL: URL, cacheTTLms: Int = 200) async throws -> OpenClawConfig {
        let store = ConfigStore(fileURL: fileURL, cacheTTLms: cacheTTLms)
        return try await store.loadCached()
    }

    public func saveConfig(_ config: OpenClawConfig, to fileURL: URL) async throws {
        let store = ConfigStore(fileURL: fileURL)
        try await store.save(config)
    }

    public func loadSessionStore(from fileURL: URL) async throws -> SessionStore {
        let store = SessionStore(fileURL: fileURL)
        try await store.load()
        return store
    }

    public func saveSessionStore(_ store: SessionStore) async throws {
        try await store.save()
    }

    public func resolveSessionKey(
        explicit: String?,
        context: SessionRoutingContext?,
        config: OpenClawConfig
    ) -> String {
        SessionKeyResolver.resolve(explicit: explicit, context: context, config: config)
    }

    public func ensurePortAvailable(_ port: Int) throws {
        try PortUtils.ensurePortAvailable(port)
    }

    public func runExec(_ command: [String], cwd: URL? = nil) async throws -> ProcessResult {
        let runner = ProcessRunner()
        return try await runner.run(command, cwd: cwd)
    }

    public func runCommandWithTimeout(
        _ command: [String],
        timeoutMs: Int,
        cwd: URL? = nil
    ) async throws -> ProcessResult {
        let timeoutNs = UInt64(max(0, timeoutMs)) * 1_000_000
        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                try await self.runExec(command, cwd: cwd)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNs)
                throw OpenClawCoreError.unavailable("Command timed out")
            }
            guard let result = try await group.next() else {
                throw OpenClawCoreError.unavailable("Command timed out")
            }
            group.cancelAll()
            return result
        }
    }

    public func ensureBinary(_ name: String) throws -> String {
        try BinaryUtils.ensureBinary(name)
    }

    public func monitorWebChannel(
        config: OpenClawConfig,
        sessionStoreURL: URL
    ) async throws -> AutoReplyEngine {
        let sessionStore = SessionStore(fileURL: sessionStoreURL)
        try await sessionStore.load()
        let channelRegistry = ChannelRegistry()
        let webchat = InMemoryChannelAdapter(id: .webchat)
        await channelRegistry.register(webchat)
        try await webchat.start()
        let runtime = EmbeddedAgentRuntime()
        return AutoReplyEngine(
            config: config,
            sessionStore: sessionStore,
            channelRegistry: channelRegistry,
            runtime: runtime
        )
    }

    public func getReplyFromConfig(
        config: OpenClawConfig,
        sessionStoreURL: URL,
        inbound: InboundMessage
    ) async throws -> OutboundMessage {
        let engine = try await monitorWebChannel(config: config, sessionStoreURL: sessionStoreURL)
        return try await engine.process(inbound)
    }

    public func waitForever() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
