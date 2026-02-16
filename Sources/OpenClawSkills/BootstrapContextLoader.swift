import Foundation

/// Loaded bootstrap context file entry.
public struct BootstrapContextFile: Sendable, Equatable {
    /// Filename.
    public let name: String
    /// Absolute source path.
    public let path: String
    /// File contents.
    public let content: String

    /// Creates a bootstrap context file entry.
    /// - Parameters:
    ///   - name: Filename.
    ///   - path: Absolute source path.
    ///   - content: File contents.
    public init(name: String, path: String, content: String) {
        self.name = name
        self.path = path
        self.content = content
    }
}

/// Snapshot containing composed bootstrap context prompt text.
public struct BootstrapPromptSnapshot: Sendable, Equatable {
    /// Composed prompt text.
    public let prompt: String
    /// Loaded source files.
    public let files: [BootstrapContextFile]

    /// Creates a bootstrap prompt snapshot.
    /// - Parameters:
    ///   - prompt: Composed prompt text.
    ///   - files: Loaded source files.
    public init(prompt: String, files: [BootstrapContextFile]) {
        self.prompt = prompt
        self.files = files
    }
}

/// Actor that loads bootstrap/personality files from a workspace.
public actor BootstrapContextLoader {
    private let workspaceRoot: URL

    /// Creates a bootstrap context loader.
    /// - Parameter workspaceRoot: Workspace root URL.
    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    /// Loads bootstrap files and returns a composed prompt snapshot.
    /// - Returns: Prompt snapshot with loaded files.
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
