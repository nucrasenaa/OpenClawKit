import Foundation

public enum BinaryUtils {
    public static func ensureBinary(_ name: String, pathEnv: String? = ProcessInfo.processInfo.environment["PATH"]) throws -> String {
        let candidates = (pathEnv ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(name).path }

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        throw OpenClawCoreError.unavailable("Binary not found on PATH: \(name)")
    }
}

