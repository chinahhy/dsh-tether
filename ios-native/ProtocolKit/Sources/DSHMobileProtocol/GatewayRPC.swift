import Foundation

/// DSH 0.2.0-rc.2 Connection unary envelope. Binary multipart responses and
/// remote.mux streams are intentionally outside this first protocol probe.
public struct GatewayRequest: Encodable {
    public let type = "client-request"
    public let rpcId: String
    public let method: String
    public let payload: GatewayPayload

    public init(rpcId: String, namespace: String, method: String, args: [String: JSONValue]) throws {
        guard Self.validSegment(namespace), Self.validSegment(method) else { throw GatewayError.invalidTarget }
        self.rpcId = rpcId
        self.method = "\(namespace)/\(method)"
        self.payload = GatewayPayload(args: args)
    }

    public var path: String { "/api/\(method)" }

    private static func validSegment(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) ||
            (48...57).contains(byte) || [36, 45, 46, 95].contains(byte)
        }
    }
}

public struct GatewayPayload: Encodable {
    public let args: [String: JSONValue]
}

public indirect enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try box.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .string(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }
}

public enum GatewayError: LocalizedError, Equatable {
    case invalidTarget
    case invalidEnvelope
    case rpcIdMismatch
    case remote(code: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidTarget:
            return "手机端请求地址无效"
        case .invalidEnvelope:
            return "电脑返回的 DSH 响应格式不兼容，请检查两端版本"
        case .rpcIdMismatch:
            return "电脑返回了不属于本次请求的响应"
        case .remote(let code, let message):
            return "DSH 请求失败（\(code)）：\(message)"
        }
    }
}

public enum GatewayResponse {
    public static func value(from data: Data, expectedRpcId: String) throws -> JSONValue {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.type == "server-response" else { throw GatewayError.invalidEnvelope }
        guard envelope.rpcId == expectedRpcId else { throw GatewayError.rpcIdMismatch }
        if envelope.result.ok == true, let value = envelope.result.value { return value }
        if envelope.result.ok == false, let error = envelope.result.error {
            throw GatewayError.remote(code: error.code, message: error.message)
        }
        throw GatewayError.invalidEnvelope
    }

    private struct Envelope: Decodable {
        let type: String
        let rpcId: String
        let result: Result
    }
    private struct Result: Decodable {
        let ok: Bool
        let value: JSONValue?
        let error: RemoteError?
    }
    private struct RemoteError: Decodable {
        let code: String
        let message: String
    }
}
