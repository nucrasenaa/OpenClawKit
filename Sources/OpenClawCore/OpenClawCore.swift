import Foundation

public enum OpenClawCoreError: Error, LocalizedError, Sendable {
    case unavailable(String)
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            return "Unavailable: \(detail)"
        case .invalidConfiguration(let detail):
            return "Invalid configuration: \(detail)"
        }
    }
}

public struct OpenClawBuildInfo: Sendable {
    public let protocolVersion: Int

    public init(protocolVersion: Int) {
        self.protocolVersion = protocolVersion
    }
}

