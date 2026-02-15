import Foundation
import Testing
@testable import OpenClawKit

@Suite("OpenClawSDK facade")
struct OpenClawSDKFacadeTests {
    @Test
    func configFacadeRoundTrip() async throws {
        let sdk = OpenClawSDK.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-facade-config", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("openclaw.json", isDirectory: false)

        let config = OpenClawConfig(gateway: GatewayConfig(host: "127.0.0.1", port: 18888, authMode: "token"))
        try await sdk.saveConfig(config, to: path)
        let loaded = try await sdk.loadConfig(from: path)
        #expect(loaded.gateway.port == 18888)
    }

    @Test
    func commandAndBinaryFacadeFunctions() async throws {
        let sdk = OpenClawSDK.shared
        let result = try await sdk.runCommandWithTimeout(["/bin/echo", "ok"], timeoutMs: 5_000)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("ok"))

        let binary = try sdk.ensureBinary("sh")
        #expect(binary.contains("sh"))
    }

    @Test
    func replyFacadeFlowReturnsOutboundMessage() async throws {
        let sdk = OpenClawSDK.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-facade-reply", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sessions = root.appendingPathComponent("sessions.json", isDirectory: false)
        let config = OpenClawConfig()

        let outbound = try await sdk.getReplyFromConfig(
            config: config,
            sessionStoreURL: sessions,
            inbound: InboundMessage(channel: .webchat, peerID: "u1", text: "hello")
        )
        #expect(outbound.text == "OK")
    }
}

