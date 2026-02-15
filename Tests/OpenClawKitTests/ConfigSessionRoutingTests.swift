import Foundation
import Testing
@testable import OpenClawCore

@Suite("Config and session routing")
struct ConfigSessionRoutingTests {
    @Test
    func configStoreRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-config-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configPath = root.appendingPathComponent("openclaw.json", isDirectory: false)

        let store = ConfigStore(fileURL: configPath, cacheTTLms: 5_000)
        let config = OpenClawConfig(
            gateway: GatewayConfig(host: "0.0.0.0", port: 18800, authMode: "password"),
            agents: AgentsConfig(defaultAgentID: "ops", workspaceRoot: "./workspace-ops"),
            routing: RoutingConfig(defaultSessionKey: "main", includeAccountID: true, includePeerID: true)
        )
        try await store.save(config)

        let loaded = try await store.load()
        #expect(loaded == config)
    }

    @Test
    func configStoreCacheCanBeCleared() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-config-cache-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("openclaw.json", isDirectory: false)

        let store = ConfigStore(fileURL: path, cacheTTLms: 60_000)
        try await store.save(OpenClawConfig(gateway: GatewayConfig(port: 18789)))
        let first = try await store.loadCached()
        #expect(first.gateway.port == 18789)

        try await store.save(OpenClawConfig(gateway: GatewayConfig(port: 19999)))
        let cached = try await store.loadCached()
        #expect(cached.gateway.port == 19999)

        await store.clearCache()
        let refreshed = try await store.loadCached()
        #expect(refreshed.gateway.port == 19999)
    }

    @Test
    func sessionKeyResolverUsesRoutingConfig() {
        let config = OpenClawConfig(
            routing: RoutingConfig(defaultSessionKey: "main", includeAccountID: true, includePeerID: true)
        )
        let context = SessionRoutingContext(channel: "telegram", accountID: "default", peerID: "1234")
        let key = SessionKeyResolver.resolve(explicit: nil, context: context, config: config)
        #expect(key == "telegram:default:1234")
    }

    @Test
    func sessionStoreResolveOrCreateTracksRoute() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-session-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("sessions.json", isDirectory: false)
        let store = SessionStore(fileURL: path)

        let created = await store.resolveOrCreate(
            sessionKey: "telegram:default:1234",
            defaultAgentID: "main",
            route: SessionRoute(channel: "telegram", accountID: "default", peerID: "1234")
        )
        #expect(created.agentID == "main")
        #expect(created.lastRoute?.channel == "telegram")

        try await store.save()
        let reloaded = SessionStore(fileURL: path)
        try await reloaded.load()
        let fetched = await reloaded.recordForKey("telegram:default:1234")
        #expect(fetched?.key == "telegram:default:1234")
    }
}

