import Foundation
import IrohLib
import Security
import DSHMobileProtocol

enum MobileConnectionError: LocalizedError {
    case notConnected
    case closed
    case invalidPairing
    case pairingRejected(String)
    case invalidHTTP
    case oversizedResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConnected: "尚未连接电脑"
        case .closed: "与电脑的连接已断开"
        case .invalidPairing: "配对格式应为「电脑 ID#六位配对码」"
        case .pairingRejected(let reason): "配对失败：\(reason)"
        case .invalidHTTP: "电脑返回了无法读取的响应"
        case .oversizedResponse: "电脑返回的数据超过手机端限制"
        case .http(let status): "电脑请求失败（HTTP \(status)）"
        }
    }
}

/// One iroh endpoint and its control stream. Every DSH request opens a separate
/// authenticated proxy stream on the already-paired connection.
actor TetherTransport {
    private var endpoint: Endpoint?
    private var connection: Connection?
    private var controlSend: SendStream?
    private var controlRecv: RecvStream?
    private var lines = WireLineBuffer()
    private var pending: [TetherWire] = []

    func connect(id: String, pairingCode: String? = nil) async throws {
        await disconnect()
        let key = try MobileIdentity.loadOrCreate()
        let ep = try await Endpoint.bind(options: EndpointOptions(
            preset: presetN0(), secretKey: key
        ))
        do {
            let peer = try EndpointId.fromString(s: id)
            let addr = EndpointAddr(id: peer, relayUrl: nil, addresses: [])
            let conn = try await ep.connect(
                addr: addr, alpn: Data(TetherWireCodec.alpn.utf8)
            )
            let stream = try await conn.openBi()
            let send = stream.send()
            let recv = stream.recv()
            endpoint = ep
            connection = conn
            controlSend = send
            controlRecv = recv
            lines = WireLineBuffer()
            pending = []
            let first: TetherWire = pairingCode.map {
                .pair(code: $0, name: "iPhone")
            } ?? .hello(name: "iPhone")
            try await send.writeAll(buf: TetherWireCodec.encode(first))
            if pairingCode != nil {
                switch try await nextControlMessage() {
                case .pairOK: break
                case .pairFail(let reason):
                    throw MobileConnectionError.pairingRejected(reason)
                default: throw MobileConnectionError.invalidPairing
                }
            }
        } catch {
            await disconnect()
            throw error
        }
    }

    func disconnect() async {
        if let connection {
            try? connection.close(errorCode: 0, reason: Data())
        }
        if let endpoint { try? await endpoint.close() }
        connection = nil
        endpoint = nil
        controlSend = nil
        controlRecv = nil
        pending = []
        lines = WireLineBuffer()
    }

    func nextControlMessage() async throws -> TetherWire {
        if !pending.isEmpty { return pending.removeFirst() }
        guard let recv = controlRecv else { throw MobileConnectionError.notConnected }
        while true {
            let bytes = try await recv.read(sizeLimit: 4096)
            guard !bytes.isEmpty else { throw MobileConnectionError.closed }
            pending.append(contentsOf: try lines.append(bytes))
            if !pending.isEmpty { return pending.removeFirst() }
        }
    }

    func decide(id: String, allow: Bool) async throws {
        guard let send = controlSend else { throw MobileConnectionError.notConnected }
        try await send.writeAll(buf: TetherWireCodec.encode(
            .decision(id: id, outcome: allow ? "allowed-once" : "rejected")
        ))
    }

    func openWebSocket() async throws -> WebSocketProxy {
        guard let connection else { throw MobileConnectionError.notConnected }
        return try await WebSocketProxy.connect(on: connection)
    }

    func clearIdentity() async {
        await disconnect()
        MobileIdentity.delete()
    }

    func request(
        path: String, method: String = "POST", body: Data = Data(),
        headers: [String: String] = [:]
    ) async throws -> Data {
        guard let connection else { throw MobileConnectionError.notConnected }
        guard path.hasPrefix("/"), !path.contains("\r"), !path.contains("\n") else {
            throw MobileConnectionError.invalidHTTP
        }
        let stream = try await connection.openBi()
        let send = stream.send()
        try await send.writeAll(buf: TetherWireCodec.encode(.proxy))
        var head = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
        for (name, value) in headers {
            guard !name.contains("\r"), !name.contains("\n"),
                  !value.contains("\r"), !value.contains("\n") else {
                throw MobileConnectionError.invalidHTTP
            }
            head += "\(name): \(value)\r\n"
        }
        if method == "POST" {
            head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        }
        head += "\r\n"
        try await send.writeAll(buf: Data(head.utf8))
        if !body.isEmpty { try await send.writeAll(buf: body) }
        try await send.finish()
        let raw = try await stream.recv().readToEnd(sizeLimit: 32 * 1024 * 1024)
        return try Self.parseHTTP(raw)
    }

    private static func parseHTTP(_ raw: Data) throws -> Data {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let boundary = raw.range(of: delimiter),
              let header = String(data: raw[..<boundary.lowerBound], encoding: .utf8),
              let statusLine = header.components(separatedBy: "\r\n").first,
              let status = Int(statusLine.split(separator: " ").dropFirst().first ?? "")
        else { throw MobileConnectionError.invalidHTTP }
        let body = Data(raw[boundary.upperBound...])
        guard (200..<300).contains(status) else { throw MobileConnectionError.http(status) }
        if header.lowercased().contains("transfer-encoding: chunked") {
            return try decodeChunked(body)
        }
        if let lengthLine = header.components(separatedBy: "\r\n").first(where: {
            $0.lowercased().hasPrefix("content-length:")
        }), let length = Int(lengthLine.split(separator: ":", maxSplits: 1).last?
            .trimmingCharacters(in: .whitespaces) ?? ""), length >= 0 {
            guard body.count >= length else { throw MobileConnectionError.invalidHTTP }
            return Data(body.prefix(length))
        }
        return body
    }

    private static func decodeChunked(_ body: Data) throws -> Data {
        let bytes = [UInt8](body)
        var offset = 0
        var result = Data()
        while offset < bytes.count {
            guard let end = (offset..<(bytes.count - 1)).first(where: {
                bytes[$0] == 13 && bytes[$0 + 1] == 10
            }), let line = String(bytes: bytes[offset..<end], encoding: .ascii),
                  let size = Int(line.split(separator: ";").first ?? "", radix: 16),
                  size >= 0 else { throw MobileConnectionError.invalidHTTP }
            offset = end + 2
            if size == 0 { return result }
            guard size <= 32 * 1024 * 1024 - result.count,
                  offset + size + 2 <= bytes.count,
                  bytes[offset + size] == 13, bytes[offset + size + 1] == 10
            else { throw MobileConnectionError.oversizedResponse }
            result.append(contentsOf: bytes[offset..<(offset + size)])
            offset += size + 2
        }
        throw MobileConnectionError.invalidHTTP
    }
}

private enum MobileIdentity {
    static let service = "com.hoya.dsh.mobile.iroh"
    static let account = "endpoint-secret-v1"

    static func loadOrCreate() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let key = item as? Data, key.count == 32 {
            return key
        }
        guard status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let generated = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard generated == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(generated))
        }
        let key = Data(bytes)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key,
        ]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(added))
        }
        return key
    }

    static func delete() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
