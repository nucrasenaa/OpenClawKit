import Foundation

public enum OpenClawFileSystem {
    public static func resolveHomeDirectory() -> URL {
        #if os(iOS) || os(tvOS) || os(watchOS)
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #else
        FileManager.default.homeDirectoryForCurrentUser
        #endif
    }

    public static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public static func readData(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public static func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    public static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

