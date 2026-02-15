import Foundation

public struct ProcessResult: Sendable {
    public let command: [String]
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(command: [String], exitCode: Int32, stdout: String, stderr: String) {
        self.command = command
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public actor ProcessRunner {
    public init() {}

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

