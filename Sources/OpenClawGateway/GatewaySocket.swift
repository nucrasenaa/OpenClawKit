import Foundation
import OpenClawCore
import OpenClawProtocol

public protocol GatewaySocket: Sendable {
    func connect(url: URL) async throws
    func send(text: String) async throws
    func receive() async throws -> String
    func close() async
}

public actor LoopbackGatewaySocket: GatewaySocket {
    private var open = false
    private var queue: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []

    public init() {}

    public func connect(url _: URL) async throws {
        self.open = true
    }

    public func send(text: String) async throws {
        guard self.open else {
            throw OpenClawCoreError.unavailable("Socket is not connected")
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let request = try decoder.decode(RequestFrame.self, from: Data(text.utf8))
        let response = ResponseFrame(
            type: "res",
            id: request.id,
            ok: true,
            payload: AnyCodable(["status": AnyCodable("accepted")]),
            error: nil
        )
        let raw = String(decoding: try encoder.encode(response), as: UTF8.self)
        self.enqueue(raw)
    }

    public func receive() async throws -> String {
        if let first = self.queue.first {
            self.queue.removeFirst()
            return first
        }

        guard self.open else {
            throw OpenClawCoreError.unavailable("Socket is closed")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    public func close() async {
        self.open = false
        let error = OpenClawCoreError.unavailable("Socket closed")
        let pending = self.waiters
        self.waiters.removeAll()
        for waiter in pending {
            waiter.resume(throwing: error)
        }
    }

    private func enqueue(_ raw: String) {
        if let waiter = self.waiters.first {
            self.waiters.removeFirst()
            waiter.resume(returning: raw)
            return
        }
        self.queue.append(raw)
    }
}

