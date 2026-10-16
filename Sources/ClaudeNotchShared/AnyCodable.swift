import Foundation

/// Parses / forwards payloads with any JSON structure.
public enum AnyCodable: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([AnyCodable].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: AnyCodable].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable: unrecognized JSON type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [AnyCodable]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: AnyCodable]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public subscript(key: String) -> AnyCodable? {
        objectValue?[key]
    }

    /// Flattens any value into a display string.
    public var displayString: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return s
        case .array(let a):
            return "[" + a.map(\.displayString).joined(separator: ", ") + "]"
        case .object(let o):
            let pairs = o.map { "\($0.key): \($0.value.displayString)" }
            return "{" + pairs.joined(separator: ", ") + "}"
        }
    }
}
