import Foundation
import OpenClawCore

/// Errors thrown when workspace path constraints are violated.
public enum WorkspaceGuardError: Error, LocalizedError, Sendable {
    /// Path resolves outside workspace root.
    case pathOutsideWorkspace(String)

    public var errorDescription: String? {
        switch self {
        case .pathOutsideWorkspace(let path):
            return "Path is outside workspace: \(path)"
        }
    }
}

/// Canonicalizes and validates paths against a workspace root jail.
public struct WorkspacePathGuard: Sendable {
    /// Canonical workspace root URL.
    public let workspaceRoot: URL
    private let normalizedRootPath: String

    /// Creates a workspace path guard.
    /// - Parameter workspaceRoot: Workspace root URL.
    public init(workspaceRoot: URL) throws {
        let normalized = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.workspaceRoot = normalized
        self.normalizedRootPath = normalized.path.hasSuffix("/") ? normalized.path : normalized.path + "/"
    }

    /// Resolves and validates a candidate path within the workspace jail.
    /// - Parameter path: Relative or absolute candidate path.
    /// - Returns: Canonicalized URL guaranteed to remain inside workspace.
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
