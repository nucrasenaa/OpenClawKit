import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public struct PortInUseError: Error, LocalizedError, Sendable {
    public let port: Int

    public init(port: Int) {
        self.port = port
    }

    public var errorDescription: String? {
        "Port \(self.port) is already in use"
    }
}

public enum PortUtils {
    public static func ensurePortAvailable(_ port: Int) throws {
        let fd = socket(AF_INET, Int32(SOCK_STREAM), 0)
        guard fd >= 0 else {
            throw OpenClawCoreError.unavailable("Unable to create socket for port check")
        }
        defer { _ = close(fd) }

        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { rawPtr in
                bind(fd, rawPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            throw PortInUseError(port: port)
        }
    }
}

