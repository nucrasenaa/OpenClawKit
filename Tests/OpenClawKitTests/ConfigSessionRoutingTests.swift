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
    func channelsConfigDefaultsLoadWhenFieldsMissing() throws {
        let legacyJSON = """
        {
          "channels": {
            "discord": {
              "enabled": true,
              "botToken": "discord-token",
              "defaultChannelID": "123"
            }
          }
        }
        """
        let decoded = try JSONDecoder().decode(OpenClawConfig.self, from: Data(legacyJSON.utf8))
        #expect(decoded.channels.discord.enabled == true)
        #expect(decoded.channels.telegram.enabled == false)
        #expect(decoded.channels.telegram.baseURL == "https://api.telegram.org")
        #expect(decoded.channels.whatsappCloud.enabled == false)
        #expect(decoded.channels.whatsappCloud.apiVersion == "v20.0")
    }

    @Test
    func channelsConfigRoundTripsExpandedChannelSettings() throws {
        let config = OpenClawConfig(
            channels: ChannelsConfig(
                discord: DiscordChannelConfig(enabled: true, botToken: "discord", defaultChannelID: "1"),
                telegram: TelegramChannelConfig(
                    enabled: true,
                    botToken: "telegram",
                    defaultChatID: "456",
                    pollIntervalMs: 3_000,
                    mentionOnly: false
                ),
                whatsappCloud: WhatsAppCloudChannelConfig(
                    enabled: true,
                    accessToken: "wa-token",
                    phoneNumberID: "pnid",
                    webhookVerifyToken: "verify-token"
                )
            )
        )
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(OpenClawConfig.self, from: encoded)
        #expect(decoded.channels.telegram.enabled == true)
        #expect(decoded.channels.telegram.defaultChatID == "456")
        #expect(decoded.channels.whatsappCloud.enabled == true)
        #expect(decoded.channels.whatsappCloud.phoneNumberID == "pnid")
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
    func sessionKeyResolverCanUseSharedFallbackAcrossChannels() {
        let config = OpenClawConfig(
            routing: RoutingConfig(
                defaultSessionKey: "shared",
                includeChannelID: false,
                includeAccountID: false,
                includePeerID: false
            )
        )
        let webchat = SessionRoutingContext(channel: "webchat", accountID: nil, peerID: "ios-local-user")
        let discord = SessionRoutingContext(channel: "discord", accountID: "user-1", peerID: "channel-1")
        let webchatKey = SessionKeyResolver.resolve(explicit: nil, context: webchat, config: config)
        let discordKey = SessionKeyResolver.resolve(explicit: nil, context: discord, config: config)
        #expect(webchatKey == "shared")
        #expect(discordKey == "shared")
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

