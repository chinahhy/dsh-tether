import CryptoKit
import Foundation
import IrohLib
import Security
import DSHMobileProtocol

/// A WebSocket carried by one authenticated tether proxy stream. The Host
/// supplies its own DSH browser cookie; the iPhone never receives that secret.
actor WebSocketProxy {
    private let send: SendStream
    private let recv: RecvStream
    private var buffer = Data()
    private let maximumFrame = 8 * 1024 * 1024

    private init(send: SendStream, recv: RecvStream) {
        self.send = send
        self.recv = recv
    }

    static func connect(on connection: Connection) async throws -> WebSocketProxy {
        let stream = try await connection.openBi()
        let socket = WebSocketProxy(send: stream.send(), recv: stream.recv())
        try await socket.handshake()
        return socket
    }

    private func handshake() async throws {
        try await send.writeAll(buf: TetherWireCodec.encode(.proxy))
        var nonce = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce)
        guard status == errSecSuccess else { throw MobileConnectionError.invalidHTTP }
        let key = Data(nonce).base64EncodedString()
        let request = [
            "GET /api/remote.mux HTTP/1.1",
            "Host: 127.0.0.1",
            "Origin: http://127.0.0.1",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Version: 13",
            "Sec-WebSocket-Key: \(key)",
            "",
            "",
        ].joined(separator: "\r\n")
        try await send.writeAll(buf: Data(request.utf8))
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil {
            guard buffer.count < 16 * 1024 else { throw MobileConnectionError.invalidHTTP }
            let chunk = try await recv.read(sizeLimit: 4096)
            guard !chunk.isEmpty else { throw MobileConnectionError.closed }
            buffer.append(chunk)
        }
        guard let boundary = buffer.range(of: separator),
              let header = String(data: buffer[..<boundary.lowerBound], encoding: .utf8),
              header.hasPrefix("HTTP/1.1 101 ") || header.hasPrefix("HTTP/1.0 101 ")
        else { throw MobileConnectionError.invalidHTTP }
        let expected = Data(Insecure.SHA1.hash(
            data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)
        )).base64EncodedString()
        guard header.components(separatedBy: "\r\n").contains(where: {
            $0.lowercased().hasPrefix("sec-websocket-accept:") &&
            $0.split(separator: ":", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces) == expected
        }) else { throw MobileConnectionError.invalidHTTP }
        buffer.removeSubrange(..<boundary.upperBound)
    }

    func sendJSON(_ value: JSONValue) async throws {
        try await sendFrame(opcode: 1, payload: JSONEncoder().encode(value))
    }

    func nextJSON() async throws -> JSONValue {
        var text = Data()
        while true {
            try await require(2)
            let first = buffer[buffer.startIndex]
            let second = buffer[buffer.startIndex + 1]
            let opcode = first & 0x0f
            let final = (first & 0x80) != 0
            guard (second & 0x80) == 0 else { throw MobileConnectionError.invalidHTTP }
            var headerSize = 2
            var length = Int(second & 0x7f)
            if length == 126 {
                try await require(4)
                length = Int(buffer[2]) << 8 | Int(buffer[3])
                headerSize = 4
            } else if length == 127 {
                try await require(10)
                let octets = buffer[2..<10]
                guard octets.prefix(4).allSatisfy({ $0 == 0 }) else {
                    throw MobileConnectionError.oversizedResponse
                }
                length = octets.reduce(0) { ($0 << 8) | Int($1) }
                headerSize = 10
            }
            guard length <= maximumFrame, text.count + length <= maximumFrame else {
                throw MobileConnectionError.oversizedResponse
            }
            try await require(headerSize + length)
            let payload = Data(buffer[headerSize..<(headerSize + length)])
            buffer.removeSubrange(..<(headerSize + length))
            if opcode == 8 { throw MobileConnectionError.closed }
            if opcode == 9 {
                try await sendFrame(opcode: 10, payload: payload)
                continue
            }
            guard opcode == 1 || opcode == 0 else { throw MobileConnectionError.invalidHTTP }
            text.append(payload)
            if final { return try JSONDecoder().decode(JSONValue.self, from: text) }
        }
    }

    func close() async {
        try? await sendFrame(opcode: 8, payload: Data())
        try? await send.finish()
    }

    private func require(_ count: Int) async throws {
        while buffer.count < count {
            let chunk = try await recv.read(sizeLimit: 16 * 1024)
            guard !chunk.isEmpty else { throw MobileConnectionError.closed }
            buffer.append(chunk)
            guard buffer.count <= maximumFrame + 16 * 1024 else {
                throw MobileConnectionError.oversizedResponse
            }
        }
    }

    private func sendFrame(opcode: UInt8, payload: Data) async throws {
        var mask = [UInt8](repeating: 0, count: 4)
        guard SecRandomCopyBytes(kSecRandomDefault, mask.count, &mask) == errSecSuccess else {
            throw MobileConnectionError.invalidHTTP
        }
        var frame = Data([0x80 | opcode])
        if payload.count < 126 {
            frame.append(UInt8(0x80 | payload.count))
        } else if payload.count <= 65_535 {
            frame.append(0x80 | 126)
            frame.append(UInt8(payload.count >> 8))
            frame.append(UInt8(payload.count & 0xff))
        } else {
            frame.append(0x80 | 127)
            let count = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((count >> shift) & 0xff))
            }
        }
        frame.append(contentsOf: mask)
        frame.append(contentsOf: payload.enumerated().map { index, byte in
            byte ^ mask[index % 4]
        })
        try await send.writeAll(buf: frame)
    }
}
