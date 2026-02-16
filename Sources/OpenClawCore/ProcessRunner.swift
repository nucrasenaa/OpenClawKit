import Foundation

/// Result payload returned from process execution.
public struct ProcessResult: Sendable {
    /// Executed command plus arguments.
    public let command: [String]
    /// Process termination status.
    public let exitCode: Int32
    /// Captured standard output.
    public let stdout: String
    /// Captured standard error.
    public let stderr: String

    /// Creates a process result.
    /// - Parameters:
    ///   - command: Executed command.
    ///   - exitCode: Process exit status.
    ///   - stdout: Captured stdout.
    ///   - stderr: Captured stderr.
    public init(command: [String], exitCode: Int32, stdout: String, stderr: String) {
        self.command = command
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

#if os(macOS) || os(Linux)
/// Actor-backed process runner for platforms that support `Process`.
public actor ProcessRunner {
    /// Creates a process runner.
    public init() {}

    /// Executes a command synchronously and captures output streams.
    /// - Parameters:
    ///   - command: Command plus arguments where the first entry is executable path.
    ///   - cwd: Optional working directory.
    /// - Returns: Process execution result.
    public func run(_ command: [String], cwd: URL? = nil) throws -> ProcessResult {
        guard let executable = command.first else {
            throw OpenClawCoreError.invalidConfiguration("Process command cannot be empty")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            command: command,
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
#else
/// Process runner fallback for platforms without `Process` availability.
public actor ProcessRunner {
    /// Creates a process runner placeholder.
    public init() {}

    /// Always throws because process execution is unavailable on this platform.
    /// - Parameters:
    ///   - command: Command plus arguments.
    ///   - cwd: Optional working directory.
    /// - Returns: Never returns successfully.
    public func run(_ command: [String], cwd: URL? = nil) throws -> ProcessResult {
        _ = command
        _ = cwd
        throw OpenClawCoreError.unavailable("Process execution is unavailable on this platform")
    }
}
#endif

