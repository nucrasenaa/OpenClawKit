import Foundation
import Testing
@testable import OpenClawKit

@Suite("Bootstrap context loader")
struct BootstrapContextLoaderTests {
    @Test
    func buildsPromptFromExistingBootstrapFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "Primary agent definition".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Persona instructions".write(
            to: root.appendingPathComponent("SOUL.md"),
            atomically: true,
            encoding: .utf8
        )

        let loader = BootstrapContextLoader(workspaceRoot: root)
        let snapshot = try await loader.loadPromptSnapshot()

        #expect(snapshot.files.map(\.name).contains("AGENTS.md"))
        #expect(snapshot.files.map(\.name).contains("SOUL.md"))
        #expect(snapshot.prompt.contains("## Workspace Bootstrap Context"))
        #expect(snapshot.prompt.contains("Primary agent definition"))
        #expect(snapshot.prompt.contains("Persona instructions"))
    }
}
