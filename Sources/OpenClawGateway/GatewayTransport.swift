import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OpenClawCore
import OpenClawProtocol

public struct GatewayEndpoint: Sendable, Equatable {
    public let url: URL
    public let serverFingerprint: String?

    public init(url: URL, serverFingerprint: String? = nil) {
        self.url = url
        self.serverFingerprint = serverFingerprint
    }
}

public struct GatewayTLSSettings: Sendable {
    public let expectedFingerprint: String?
    public let required: Bool

    public init(expectedFingerprint: String? = nil, required: Bool = false) {
        self.expectedFingerprint = expectedFingerprint
        self.required = required
    }
}

public enum GatewayTransportError: Error, LocalizedError, Sendable {
    case notConnected
    case requestTimeout(requestID: String)
    case invalidFrame(String)
    case tlsFingerprintMismatch

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Gateway is not connected"
        case .requestTimeout(let requestID):
            return "Gateway request timed out (\(requestID))"
        case .invalidFrame(let detail):
            return "Invalid gateway frame: \(detail)"
        case .tlsFingerprintMismatch:
            return "Gateway TLS fingerprint mismatch"
        }
    }
}

public actor GatewayClient {
    public typealias SocketFactory = @Sendable () -> any GatewaySocket
    public typealias EventHandler = @Sendable (EventFrame) async -> Void

    private let socketFactory: SocketFactory
    private let tls: GatewayTLSSettings
    private let onEvent: EventHandler?
    private let tickIntervalMs: Int
    private let initialReconnectBackoffMs: UInt64
    private let tickTimeoutMultiplier = 2

    private var socket: (any GatewaySocket)?
    private var receiveTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var shouldReconnect = false
    private var endpoint: GatewayEndpoint?
    private var connected = false
    private var lastTick = Date()
    private var reconnectBackoffMs: UInt64 = 500
    private var pending: [String: CheckedContinuation<ResponseFrame, Error>] = [:]

    public init(
        socketFactory: @escaping SocketFactory = { LoopbackGatewaySocket() },
        tls: GatewayTLSSettings = GatewayTLSSettings(),
        tickIntervalMs: Int = 30_000,
        initialReconnectBackoffMs: UInt64 = 500,
        onEvent: EventHandler? = nil
    ) {
        self.socketFactory = socketFactory
        self.tls = tls
        self.tickIntervalMs = max(10, tickIntervalMs)
        self.initialReconnectBackoffMs = max(10, initialReconnectBackoffMs)
        self.onEvent = onEvent
        self.reconnectBackoffMs = max(10, initialReconnectBackoffMs)
    }

    public func connect(to endpoint: GatewayEndpoint) async throws {
        self.endpoint = endpoint
        self.shouldReconnect = true
        try await self.establishConnection()
    }

    public func disconnect() async {
        self.shouldReconnect = false
        self.reconnectTask?.cancel()
        self.reconnectTask = nil
        self.receiveTask?.cancel()
        self.receiveTask = nil
        self.watchdogTask?.cancel()
        self.watchdogTask = nil
        if let socket = self.socket {
            await socket.close()
        }
        self.socket = nil
        self.failAllPending(with: GatewayTransportError.notConnected)
        self.connected = false
        self.endpoint = nil
    }

    public func isConnected() -> Bool {
        self.connected
    }

    public func send(
        method: String,
        params: [String: AnyCodable] = [:],
        timeoutMs: Int = 15_000
    ) async throws -> ResponseFrame
    {
        guard self.connected, let socket = self.socket else {
            throw GatewayTransportError.notConnected
        }

        let id = UUID().uuidString
        let frame = RequestFrame(type: "req", id: id, method: method, params: AnyCodable(params))
        let raw = String(decoding: try JSONEncoder().encode(frame), as: UTF8.self)

        return try await withCheckedThrowingContinuation { continuation in
            self.pending[id] = continuation

            Task { [weak self] in
                do {
                    try await socket.send(text: raw)
                } catch {
                    await self?.failPending(id: id, with: error)
                }
            }

            let timeoutNs = UInt64(max(0, timeoutMs)) * 1_000_000
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNs)
                await self?.failPending(id: id, with: GatewayTransportError.requestTimeout(requestID: id))
            }
        }
    }

    private func establishConnection() async throws {
        guard let endpoint else {
            throw GatewayTransportError.notConnected
        }

        try self.validateTLS(for: endpoint)

        self.receiveTask?.cancel()
        self.watchdogTask?.cancel()
        self.reconnectTask?.cancel()
        self.reconnectTask = nil

        let socket = self.socketFactory()
        try await socket.connect(url: endpoint.url)
        self.socket = socket
        self.connected = true
        self.lastTick = Date()
        self.reconnectBackoffMs = self.initialReconnectBackoffMs

        self.startReceiveLoop(using: socket)
        self.startTickWatchdog()
    }

    private func startReceiveLoop(using socket: any GatewaySocket) {
        self.receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let raw = try await socket.receive()
                    await self?.handleInbound(raw)
                } catch {
                    await self?.handleSocketFailure(error)
                    return
                }
            }
        }
    }

    private func startTickWatchdog() {
        self.watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sleepNs = UInt64(self.tickIntervalMs) * 1_000_000
                try? await Task.sleep(nanoseconds: sleepNs)
                await self.validateTickDeadline()
            }
        }
    }

    private func validateTickDeadline() {
        guard self.connected else { return }
        let timeoutSeconds = TimeInterval(self.tickIntervalMs * self.tickTimeoutMultiplier) / 1000
        guard Date().timeIntervalSince(self.lastTick) >= timeoutSeconds else { return }

        Task { [weak self] in
            if let socket = await self?.socket {
                await socket.close()
            }
            await self?.handleSocketFailure(GatewayTransportError.requestTimeout(requestID: "tick"))
        }
    }

    private func handleInbound(_ raw: String) {
        guard let data = raw.data(using: .utf8) else {
            return
        }
        do {
            let frame = try JSONDecoder().decode(GatewayFrame.self, from: data)
            switch frame {
            case .res(let response):
                self.resolvePending(id: response.id, with: response)
            case .event(let event):
                if event.event == "tick" {
                    self.lastTick = Date()
                }
                if let onEvent = self.onEvent {
                    Task {
                        await onEvent(event)
                    }
                }
            case .req:
                break
            }
        } catch {
            // Ignore malformed frames in loopback contexts; production sockets should enforce framing.
        }
    }

    private func resolvePending(id: String, with response: ResponseFrame) {
        guard let pending = self.pending.removeValue(forKey: id) else { return }
        pending.resume(returning: response)
    }

    private func failPending(id: String, with error: Error) {
        guard let pending = self.pending.removeValue(forKey: id) else { return }
        pending.resume(throwing: error)
    }

    private func failAllPending(with error: Error) {
        let unresolved = self.pending.values
        self.pending.removeAll()
        for continuation in unresolved {
            continuation.resume(throwing: error)
        }
    }

    private func handleSocketFailure(_ error: Error) {
        self.connected = false
        self.failAllPending(with: error)
        self.receiveTask?.cancel()
        self.receiveTask = nil
        self.watchdogTask?.cancel()
        self.watchdogTask = nil

        guard self.shouldReconnect, self.endpoint != nil else { return }
        self.scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard self.reconnectTask == nil else { return }
        let delay = self.reconnectBackoffMs
        self.reconnectBackoffMs = min(delay * 2, 5_000)

        self.reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000)
            guard let self else { return }
            do {
                try await self.establishConnection()
            } catch {
                await self.handleSocketFailure(error)
            }
            await self.clearReconnectTaskIfFinished()
        }
    }

    private func clearReconnectTaskIfFinished() {
        self.reconnectTask = nil
    }

    private func validateTLS(for endpoint: GatewayEndpoint) throws {
        guard endpoint.url.scheme?.lowercased() == "wss" else {
            return
        }

        let expected = self.tls.expectedFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expected, !expected.isEmpty else {
            if self.tls.required {
                throw GatewayTransportError.tlsFingerprintMismatch
            }
            return
        }

        let actual = endpoint.serverFingerprint ?? ""
        let normalizedExpected = OpenClawSecurity.normalizeFingerprint(expected)
        let normalizedActual = OpenClawSecurity.normalizeFingerprint(actual)
        guard !normalizedActual.isEmpty, normalizedExpected == normalizedActual else {
            throw GatewayTransportError.tlsFingerprintMismatch
        }
    }
}

