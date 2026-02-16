import Foundation
import OpenClawCore

#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// Result payload from JavaScript skill execution.
public struct JSSkillExecutionResult: Sendable, Equatable {
    /// Return value converted to string.
    public let output: String
    /// Collected logs emitted by the script via `log(...)`.
    public let logs: [String]

    /// Creates a JS skill execution result.
    /// - Parameters:
    ///   - output: Return value converted to string.
    ///   - logs: Captured logs.
    public init(output: String, logs: [String]) {
        self.output = output
        self.logs = logs
    }
}

/// JavaScriptCore-based executor for workspace-scoped skill scripts.
public actor JSSkillExecutor {
    private let pathGuard: WorkspacePathGuard

    /// Creates a JavaScript skill executor.
    /// - Parameter workspaceRoot: Workspace root used for path-jail enforcement.
    public init(workspaceRoot: URL) throws {
        self.pathGuard = try WorkspacePathGuard(workspaceRoot: workspaceRoot)
    }

    /// Executes JavaScript inside a restricted host API surface.
    /// - Parameters:
    ///   - script: JavaScript body to execute.
    ///   - input: Optional input payload exposed as `input`.
    /// - Returns: Script output and captured logs.
    public func execute(script: String, input: String = "") throws -> JSSkillExecutionResult {
        #if canImport(JavaScriptCore)
        guard let context = JSContext() else {
            throw OpenClawCoreError.unavailable("Unable to initialize JavaScript context")
        }

        var logs: [String] = []
        var executionError: Error?

        context.exceptionHandler = { _, exception in
            if let exception {
                executionError = OpenClawCoreError.unavailable("JavaScript exception: \(exception)")
            }
        }

        let log: @convention(block) (String) -> Void = { message in
            logs.append(message)
        }
        context.setObject(log, forKeyedSubscript: "log" as NSString)

        let readFile: @convention(block) (String) -> String = { [pathGuard] path in
            do {
                let resolved = try pathGuard.resolve(path)
                return try String(contentsOf: resolved, encoding: .utf8)
            } catch {
                executionError = error
                return ""
            }
        }
        context.setObject(readFile, forKeyedSubscript: "readFile" as NSString)

        let writeFile: @convention(block) (String, String) -> Bool = { [pathGuard] path, content in
            do {
                let resolved = try pathGuard.resolve(path)
                try FileManager.default.createDirectory(
                    at: resolved.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try content.write(to: resolved, atomically: true, encoding: .utf8)
                return true
            } catch {
                executionError = error
                return false
            }
        }
        context.setObject(writeFile, forKeyedSubscript: "writeFile" as NSString)

        let mkdir: @convention(block) (String) -> Bool = { [pathGuard] path in
            do {
                let resolved = try pathGuard.resolve(path)
                try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
                return true
            } catch {
                executionError = error
                return false
            }
        }
        context.setObject(mkdir, forKeyedSubscript: "mkdir" as NSString)

        let exists: @convention(block) (String) -> Bool = { [pathGuard] path in
            do {
                let resolved = try pathGuard.resolve(path)
                return FileManager.default.fileExists(atPath: resolved.path)
            } catch {
                executionError = error
                return false
            }
        }
        context.setObject(exists, forKeyedSubscript: "exists" as NSString)

        context.setObject(input, forKeyedSubscript: "__oc_input" as NSString)
        let wrapped = """
        (function(input) {
        \(script)
        })(__oc_input);
        """
        let outputValue = context.evaluateScript(wrapped)

        if let executionError {
            throw executionError
        }

        return JSSkillExecutionResult(output: outputValue?.toString() ?? "", logs: logs)
        #else
        _ = script
        _ = input
        throw OpenClawCoreError.unavailable("JavaScriptCore is unavailable on this platform")
        #endif
    }
}
