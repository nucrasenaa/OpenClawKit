import Foundation

public let GATEWAY_PROTOCOL_VERSION = 3

public enum ErrorCode: String, Codable, Sendable {
    case notLinked = "NOT_LINKED"
    case notPaired = "NOT_PAIRED"
    case agentTimeout = "AGENT_TIMEOUT"
    case invalidRequest = "INVALID_REQUEST"
    case unavailable = "UNAVAILABLE"
}

public struct RequestFrame: Codable, Sendable {
    public let type: String
    public let id: String
    public let method: String
    public let params: [String: String]?

    public init(type: String, id: String, method: String, params: [String: String]? = nil) {
        self.type = type
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct ResponseFrame: Codable, Sendable {
    public let type: String
    public let id: String
    public let ok: Bool
    public let payload: [String: String]?
    public let error: ErrorShape?

    public init(
        type: String,
        id: String,
        ok: Bool,
        payload: [String: String]? = nil,
        error: ErrorShape? = nil
    ) {
        self.type = type
        self.id = id
        self.ok = ok
        self.payload = payload
        self.error = error
    }
}

public struct EventFrame: Codable, Sendable {
    public let type: String
    public let event: String
    public let payload: [String: String]?
    public let seq: Int?

    public init(type: String, event: String, payload: [String: String]? = nil, seq: Int? = nil) {
        self.type = type
        self.event = event
        self.payload = payload
        self.seq = seq
    }
}

public enum GatewayFrame: Codable, Sendable {
    case req(RequestFrame)
    case res(ResponseFrame)
    case event(EventFrame)
}

public struct ErrorShape: Codable, Sendable {
    public let code: ErrorCode
    public let message: String

    public init(code: ErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

