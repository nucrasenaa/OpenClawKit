import Foundation

/// Type-erased `Codable` wrapper restricted to Sendable JSON-compatible values.
public struct AnyCodable: Codable, Sendable, Equatable {
    /// Wrapped type-erased value.
    public let value: AnySendableValue

    /// Creates a wrapper from a Sendable value.
    /// - Parameter value: Value to wrap.
    public init(_ value: some Sendable) {
        self.value = AnySendableValue(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = AnySendableValue.null
        } else if let v = try? container.decode(Bool.self) {
            self.value = AnySendableValue(v)
        } else if let v = try? container.decode(Int.self) {
            self.value = AnySendableValue(v)
        } else if let v = try? container.decode(Double.self) {
            self.value = AnySendableValue(v)
        } else if let v = try? container.decode(String.self) {
            self.value = AnySendableValue(v)
        } else if let v = try? container.decode([String: AnyCodable].self) {
            self.value = AnySendableValue(v)
        } else if let v = try? container.decode([AnyCodable].self) {
            self.value = AnySendableValue(v)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON type")
        }
    }

    /// Encodes wrapped value to a single-value container.
    /// - Parameter encoder: Target encoder.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self.value {
        case .null:
            try container.encodeNil()
        case .bool(let v):
            try container.encode(v)
        case .int(let v):
            try container.encode(v)
        case .double(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .object(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v)
        }
    }
}

/// Internal representation for type-erased JSON values.
public enum AnySendableValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case object([String: AnyCodable])
    case array([AnyCodable])

    /// Creates a type-erased value from common Sendable primitives.
    /// - Parameter value: Input value.
    public init(_ value: some Sendable) {
        switch value {
        case let v as Bool:
            self = .bool(v)
        case let v as Int:
            self = .int(v)
        case let v as Double:
            self = .double(v)
        case let v as String:
            self = .string(v)
        case let v as [String: AnyCodable]:
            self = .object(v)
        case let v as [AnyCodable]:
            self = .array(v)
        default:
            self = .string(String(describing: value))
        }
    }
}

