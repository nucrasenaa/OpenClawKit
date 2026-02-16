import Foundation
import OpenClawCore

public enum WorkspaceGuardError: Error, LocalizedError, Sendable {
    case pathOutsideWorkspace(String)

    public var errorDescription: String? {
        switch self {
        case .pathOutsideWorkspace(let path):
            return "Path is outside workspace: \(path)"
        }
    }
}

public struct WorkspacePathGuard: Sendable {
    public let workspaceRoot: URL
    private let normalizedRootPath: String

    public init(workspaceRoot: URL) throws {
        let normalized = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.workspaceRoot = normalized
        self.normalizedRootPath = normalized.path.hasSuffix("/") ? normalized.path : normalized.path + "/"
    }

    public func resolve(_ path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL: URL
        if trimmed.hasPrefix("/") {
            baseURL = URL(fileURLWithPath: trimmed)
        } else {
            baseURL = self.workspaceRoot.appendingPathComponent(trimmed)
        }

        let normalized = baseURL.standardizedFileURL.resolvingSymlinksInPath()
        if normalized.path == self.workspaceRoot.path || normalized.path.hasPrefix(self.normalizedRootPath) {
            return normalized
        }
        throw WorkspaceGuardError.pathOutsideWorkspace(path)
    }
}
