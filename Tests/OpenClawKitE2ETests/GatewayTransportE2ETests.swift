import Foundation
import Testing
@testable import OpenClawKit

@Suite("Gateway transport")
struct GatewayTransportE2ETests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            self.lock.lock()
            self.value += 1
            self.lock.unlock()
        }

        func get() -> Int {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.value
        }
    }

    actor NoTickSocket: GatewaySocket {
        func connect(url _: URL) async throws {}
        func send(text _: String) async throws {}
        func receive() async throws -> String {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw GatewayTransportError.notConnected
        }

        func close() async {}
    }

    @Test
    func connectAndRequestRoundTrip() async throws {
        let client = GatewayClient()
        try await client.connect(to: GatewayEndpoint(url: URL(string: "ws://127.0.0.1:18789")!))
        let response = try await client.send(method: "connect")
        #expect(response.ok == true)
        await client.disconnect()
    }

    @Test
    func tlsFingerprintMismatchFailsConnect() async {
        let client = GatewayClient(
            tls: GatewayTLSSettings(expectedFingerprint: "deadbeef", required: true)
        )

        do {
            try await client.connect(
                to: GatewayEndpoint(
                    url: URL(string: "wss://127.0.0.1:18789")!,
                    serverFingerprint: "cafebabe"
                )
            )
            Issue.record("Expected TLS mismatch error")
        } catch {
            #expect(String(describing: error).lowercased().contains("fingerprint"))
        }
    }

    @Test
    func tickTimeoutTriggersReconnect() async throws {
        let counter = Counter()
        let client = GatewayClient(
            socketFactory: {
                counter.increment()
                return NoTickSocket()
            },
            tickIntervalMs: 20,
            initialReconnectBackoffMs: 25
        )

        try await client.connect(to: GatewayEndpoint(url: URL(string: "ws://127.0.0.1:18789")!))
        try await Task.sleep(nanoseconds: 350_000_000)
        #expect(counter.get() > 1)
        await client.disconnect()
    }
}

