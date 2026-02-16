import Foundation

public struct BootstrapContextFile: Sendable, Equatable {
    public let name: String
    public let path: String
    public let content: String

    public init(name: String, path: String, content: String) {
        self.name = name
        self.path = path
        self.content = content
    }
}

public struct BootstrapPromptSnapshot: Sendable, Equatable {
    public let prompt: String
    public let files: [BootstrapContextFile]

    public init(prompt: String, files: [BootstrapContextFile]) {
        self.prompt = prompt
        self.files = files
    }
}

public actor BootstrapContextLoader {
    private let workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    public func loadPromptSnapshot() throws -> BootstrapPromptSnapshot {
        let files = try self.loadExistingFiles()
        guard !files.isEmpty else {
            return BootstrapPromptSnapshot(prompt: "", files: [])
        }

        var lines: [String] = ["## Workspace Bootstrap Context"]
        for file in files {
            lines.append("")
            lines.append("### \(file.name)")
            lines.append(file.content)
        }
        return BootstrapPromptSnapshot(prompt: lines.joined(separator: "\n"), files: files)
    }

    private func loadExistingFiles() throws -> [BootstrapContextFile] {
        let names = [
            "AGENTS.md",
            "SOUL.md",
            "TOOLS.md",
            "IDENTITY.md",
            "USER.md",
            "HEARTBEAT.md",
            "BOOTSTRAP.md",
            "MEMORY.md",
            "memory.md",
        ]

        var files: [BootstrapContextFile] = []
        for name in names {
            let fileURL = self.workspaceRoot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                continue
            }
            files.append(BootstrapContextFile(name: name, path: fileURL.path, content: content))
        }
        return files
    }
}
