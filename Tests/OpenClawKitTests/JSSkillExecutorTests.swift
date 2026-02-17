import Foundation
import Testing
@testable import OpenClawKit

#if canImport(JavaScriptCore)
@Suite("JavaScript skill executor")
struct JSSkillExecutorTests {
    @Test
    func blocksPathTraversalOutsideWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outside) }

        let executor = try JSSkillExecutor(workspaceRoot: root)
        do {
            _ = try await executor.execute(script: """
            writeFile("../\(outside.lastPathComponent)", "blocked");
            return "ok";
            """)
            Issue.record("Expected traversal rejection")
        } catch {
            let message = String(describing: error).lowercased()
            #expect(message.contains("outsideworkspace") || message.contains("outside workspace"))
        }

        #expect(!FileManager.default.fileExists(atPath: outside.path))
    }

    @Test
    func allowsReadWriteWithinWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executor = try JSSkillExecutor(workspaceRoot: root)
        let result = try await executor.execute(script: """
        mkdir("state");
        writeFile("state/result.txt", "hello-js");
        const value = readFile("state/result.txt");
        log("read:" + value);
        return value;
        """)

        #expect(result.output == "hello-js")
        #expect(result.logs.contains(where: { $0.contains("read:hello-js") }))
        let filePath = root.appendingPathComponent("state").appendingPathComponent("result.txt").path
        #expect(FileManager.default.fileExists(atPath: filePath))
    }

    @Test
    func executesScriptFileWithinWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let scriptDir = root.appendingPathComponent("skills").appendingPathComponent("weather")
        try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)
        let scriptFile = scriptDir.appendingPathComponent("skill.js")
        try """
        log("running weather script");
        return "weather-ok";
        """.write(to: scriptFile, atomically: true, encoding: .utf8)

        let executor = try JSSkillExecutor(workspaceRoot: root)
        let result = try await executor.executeFile(scriptPath: "skills/weather/skill.js")
        #expect(result.output == "weather-ok")
        #expect(result.logs.contains(where: { $0.contains("running weather script") }))
    }

    @Test
    func rejectsUnsupportedHttpGetScheme() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executor = try JSSkillExecutor(workspaceRoot: root)
        do {
            _ = try await executor.execute(script: """
            const body = httpGet("ftp://example.com");
            return body;
            """)
            Issue.record("Expected unsupported scheme failure")
        } catch {
            let message = String(describing: error).lowercased()
            #expect(message.contains("http") && message.contains("supports"))
        }
    }
}
#else
@Suite("JavaScript skill executor")
struct JSSkillExecutorTests {
    @Test
    func skippedWhenJavaScriptCoreUnavailable() {
        #expect(true)
    }
}
#endif
