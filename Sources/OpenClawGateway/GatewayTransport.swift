import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OpenClawCore
import OpenClawProtocol

public struct GatewayEndpoint: Sendable, Equatable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public actor GatewayClient {
    private var endpoint: GatewayEndpoint?
    private var connected = false
    private var nextSequence = 0

    public init() {}

    public func connect(to endpoint: GatewayEndpoint) async throws {
        self.endpoint = endpoint
        self.connected = true
    }

    public func disconnect() async {
        self.connected = false
        self.endpoint = nil
    }

    public func isConnected() -> Bool {
        self.connected
    }

    public func send(
        method: String,
        params: [String: AnyCodable] = [:]
    ) async throws -> ResponseFrame
    {
        guard self.connected, self.endpoint != nil else {
            throw OpenClawCoreError.unavailable("Gateway is not connected")
        }
        let id = UUID().uuidString
        self.nextSequence += 1
        _ = RequestFrame(type: "req", id: id, method: method, params: AnyCodable(params))
        return ResponseFrame(
            type: "res",
            id: id,
            ok: true,
            payload: AnyCodable(["status": AnyCodable("accepted")]),
            error: nil
        )
    }
}

