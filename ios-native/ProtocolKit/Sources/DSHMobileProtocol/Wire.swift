import Foundation

/// The Mac displays the endpoint ID and short-lived numeric code as one string.
/// Whitespace may be introduced when copying a visually wrapped field.
public struct PairingTicket: Equatable, Sendable {
    public let endpointId: String
    public let code: String

    public init?(raw: String) {
        let compact = raw.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }.map(String.init).joined()
        let parts = compact.split(separator: "#", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].utf8.count == 64,
              parts[0].utf8.allSatisfy({
                  ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102)
              }),
              parts[1].utf8.count == 6,
              parts[1].utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
        else { return nil }
        endpointId = String(parts[0]).lowercased()
        code = String(parts[1])
    }
}

/// The existing tether-core Wire enum, without transport or identity storage.
/// This package deliberately cannot open a network connection or touch DSH data.
public enum TetherWire: Equatable, Sendable {
    case hello(name: String)
    case pair(code: String, name: String)
    case proxy
    case pairOK
    case pairFail(reason: String)
    case approval(id: String, toolName: String, reason: String)
    case approvalCancel(id: String)
    case decision(id: String, outcome: String)
}

public enum WireError: Error, Equatable {
    case oversizedLine
    case malformedLine
    case unknownType
}

public enum TetherWireCodec {
    public static let alpn = "dsh-tether/0"
    public static let maximumLineBytes = 64 * 1024
    public static let maximumUnpairedLineBytes = 512

    public static func decode(_ line: Data, unpaired: Bool = false) throws -> TetherWire {
        let limit = unpaired ? maximumUnpairedLineBytes : maximumLineBytes
        guard line.count <= limit else { throw WireError.oversizedLine }
        guard !line.contains(10), let string = String(data: line, encoding: .utf8),
              let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { throw WireError.malformedLine }
        func field(_ name: String) throws -> String {
            guard let value = object[name] as? String else { throw WireError.malformedLine }
            return value
        }
        switch type {
        case "hello": return .hello(name: try field("name"))
        case "pair": return .pair(code: try field("code"), name: try field("name"))
        case "proxy": return .proxy
        case "pair-ok": return .pairOK
        case "pair-fail": return .pairFail(reason: try field("reason"))
        case "approval": return .approval(id: try field("id"), toolName: try field("tool_name"), reason: try field("reason"))
        case "approval-cancel": return .approvalCancel(id: try field("id"))
        case "decision": return .decision(id: try field("id"), outcome: try field("outcome"))
        default: throw WireError.unknownType
        }
    }

    public static func encode(_ message: TetherWire) throws -> Data {
        var fields: [String: String]
        switch message {
        case .hello(let name): fields = ["type": "hello", "name": name]
        case .pair(let code, let name): fields = ["type": "pair", "code": code, "name": name]
        case .proxy: fields = ["type": "proxy"]
        case .pairOK: fields = ["type": "pair-ok"]
        case .pairFail(let reason): fields = ["type": "pair-fail", "reason": reason]
        case .approval(let id, let toolName, let reason):
            fields = ["type": "approval", "id": id, "tool_name": toolName, "reason": reason]
        case .approvalCancel(let id): fields = ["type": "approval-cancel", "id": id]
        case .decision(let id, let outcome):
            fields = ["type": "decision", "id": id, "outcome": outcome]
        }
        let bytes = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        guard bytes.count <= maximumLineBytes else { throw WireError.oversizedLine }
        return bytes + Data([10])
    }
}

/// Reads a JSON-lines control stream without allowing an unbounded partial line.
public struct WireLineBuffer {
    private var partial = Data()
    private let limit: Int

    public init(unpaired: Bool = false) {
        limit = unpaired ? TetherWireCodec.maximumUnpairedLineBytes : TetherWireCodec.maximumLineBytes
    }

    public mutating func append(_ bytes: Data) throws -> [TetherWire] {
        var messages: [TetherWire] = []
        for byte in bytes {
            if byte == 10 {
                messages.append(try TetherWireCodec.decode(partial, unpaired: limit == TetherWireCodec.maximumUnpairedLineBytes))
                partial.removeAll(keepingCapacity: true)
            } else {
                partial.append(byte)
                if partial.count > limit { throw WireError.oversizedLine }
            }
        }
        return messages
    }
}
