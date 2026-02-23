import Foundation
import Testing
@testable import OpenClawKit

@Suite("Security audit")
struct SecurityAuditTests {
    @Test
    func auditFindsRiskyDefaultsAndPlaintextSecrets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-security-audit-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.json", isDirectory: false)
        try """
        {
          "openAI": { "apiKey": "plaintext-key" },
          "discord": { "botToken": "plaintext-token" }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        #if !os(Windows)
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o666))], ofItemAtPath: configURL.path)
        #endif

        let config = OpenClawConfig(
            gateway: GatewayConfig(authMode: "none"),
            channels: ChannelsConfig(
                discord: DiscordChannelConfig(enabled: true, botToken: "token", mentionOnly: false),
                telegram: TelegramChannelConfig(enabled: true, botToken: "token", mentionOnly: false)
            ),
            routing: RoutingConfig(
                defaultSessionKey: "shared",
                includeChannelID: false,
                includeAccountID: false,
                includePeerID: false
            ),
            models: ModelsConfig(local: LocalModelConfig(enabled: true, modelPath: nil))
        )

        let report = SecurityAuditRunner.run(
            options: SecurityAuditOptions(
                config: config,
                configFileURL: configURL,
                statePaths: [root]
            )
        )

        #expect(report.highestSeverity == .error)
        #expect(report.findings.contains(where: { $0.id == "gateway.auth-mode-unsafe" }))
        #expect(report.findings.contains(where: { $0.id == "routing.shared-session" }))
        #expect(report.findings.contains(where: { $0.id == "secrets.config.plaintext" }))
        #expect(report.findings.contains(where: { $0.id.starts(with: "plaintext.file.") }))
        #expect(report.count(for: SecurityAuditSeverity.warning) >= 1)
    }

    @Test
    func auditIsCleanForHardenedConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-security-audit-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.json", isDirectory: false)
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)
        #if !os(Windows)
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: root.path)
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: configURL.path)
        #endif

        let report = SecurityAuditRunner.run(
            options: SecurityAuditOptions(
                config: OpenClawConfig(),
                configFileURL: configURL,
                statePaths: [root]
            )
        )

        #expect(report.findings.isEmpty)
        #expect(report.highestSeverity == .info)
        #expect(report.hasBlockingFindings == false)
    }

    @Test
    func sdkAuditPublishesDiagnosticsEvents() async {
        let sdk = OpenClawSDK.shared
        let pipeline = RuntimeDiagnosticsPipeline(eventLimit: 50)
        let report = await sdk.runSecurityAudit(
            options: SecurityAuditOptions(
                config: OpenClawConfig(gateway: GatewayConfig(authMode: "none"))
            ),
            diagnosticsPipeline: pipeline
        )

        #expect(report.findings.contains(where: { $0.id == "gateway.auth-mode-unsafe" }))
        let events = await pipeline.recentEvents(limit: 50)
        #expect(events.contains(where: { $0.subsystem == "security" && $0.name == "audit.completed" }))
        #expect(events.contains(where: { $0.subsystem == "security" && $0.name == "audit.finding" }))
    }
}
