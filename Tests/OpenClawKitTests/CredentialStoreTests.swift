import Foundation
import Testing
@testable import OpenClawCore

@Suite("Credential stores")
struct CredentialStoreTests {
    @Test
    func fileCredentialStoreRoundTripAndDelete() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("credentials.json")
        let store = FileCredentialStore(fileURL: storeURL)

        try await store.saveSecret("secret-value", for: "openai")
        let loaded = try await store.loadSecret(for: "openai")
        #expect(loaded == "secret-value")

        try await store.deleteSecret(for: "openai")
        let deleted = try await store.loadSecret(for: "openai")
        #expect(deleted == nil)
    }

    @Test
    func fileCredentialStorePersistsAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclawkit-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("credentials.json")
        let first = FileCredentialStore(fileURL: storeURL)
        try await first.saveSecret("discord-token", for: "discord")

        let second = FileCredentialStore(fileURL: storeURL)
        let loaded = try await second.loadSecret(for: "discord")
        #expect(loaded == "discord-token")
    }

    @Test
    func defaultFactorySelectsExpectedStoreForPlatform() {
        let fallbackURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("credentials.json")
        let store = CredentialStoreFactory.makeDefault(
            fallbackFileURL: fallbackURL,
            keychainService: "io.marcodotio.openclawkit.tests.\(UUID().uuidString)"
        )

        #if canImport(Security)
        #expect(store is KeychainCredentialStore)
        #else
        #expect(store is FileCredentialStore)
        #endif
    }

    #if canImport(Security)
    @Test
    func keychainCredentialStoreRoundTripAndDelete() async throws {
        let service = "io.marcodotio.openclawkit.tests.\(UUID().uuidString)"
        let key = "anthropic"
        let store = KeychainCredentialStore(service: service)

        defer {
            Task {
                try? await store.deleteSecret(for: key)
            }
        }

        try await store.saveSecret("anthropic-secret", for: key)
        let loaded = try await store.loadSecret(for: key)
        #expect(loaded == "anthropic-secret")

        try await store.deleteSecret(for: key)
        let deleted = try await store.loadSecret(for: key)
        #expect(deleted == nil)
    }
    #endif
}
