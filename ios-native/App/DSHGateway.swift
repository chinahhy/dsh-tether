import Foundation
import DSHMobileProtocol

extension JSONValue {
    var fields: [String: JSONValue] {
        if case .object(let fields) = self { return fields }
        return [:]
    }

    var items: [JSONValue] {
        if case .array(let items) = self { return items }
        return []
    }

    var text: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

struct RemoteSession: Identifiable, Equatable {
    let id: String
    let title: String
    let cwd: String
    let mode: String
    let running: Bool
    let updatedAt: Date

    init?(_ value: JSONValue) {
        let fields = value.fields
        guard let id = fields["sessionId"]?.text else { return nil }
        let cwd = fields["cwd"]?.text ?? ""
        let values = fields["projections"]?.fields["values"]?.fields ?? [:]
        self.id = id
        self.cwd = cwd
        self.title = values["title"]?.text.flatMap { $0.isEmpty ? nil : $0 }
            ?? (cwd.isEmpty ? "未命名会话" : URL(fileURLWithPath: cwd).lastPathComponent)
        self.mode = values["agentPreset"]?.text ?? "standard"
        self.running = fields["running"]?.boolValue ?? false
        self.updatedAt = Date(timeIntervalSince1970:
            (fields["updatedAt"]?.numberValue ?? 0) / 1000)
    }
}

struct RemoteMessage: Identifiable, Equatable {
    let id: Int
    let fromUser: Bool
    let text: String
    let time: Date

    init?(_ value: JSONValue) {
        let event = value.fields["event"]?.fields ?? [:]
        guard let kind = event["type"]?.text,
              kind == "user/message" || kind == "assistant/message",
              let seq = event["seq"]?.numberValue else { return nil }
        let data = event["data"]?.fields ?? [:]
        let content = kind == "user/message"
            ? data["content"]?.items ?? []
            : data["message"]?.fields["content"]?.items ?? []
        let fragments = content.compactMap { item -> String? in
            guard item.fields["type"]?.text == "text" else { return nil }
            return item.fields["text"]?.text
        }
        guard !fragments.isEmpty else { return nil }
        self.id = Int(seq)
        self.fromUser = kind == "user/message"
        self.text = fragments.joined(separator: "\n")
        self.time = Date(timeIntervalSince1970:
            (event["time"]?.numberValue ?? 0) / 1000)
    }
}

struct PendingApproval: Identifiable, Equatable {
    let id: String
    let toolName: String
    let reason: String
}

actor DSHGateway {
    private let transport: TetherTransport

    init(transport: TetherTransport) {
        self.transport = transport
    }

    private func call(_ method: String, request: JSONValue? = nil) async throws -> JSONValue {
        let rpcId = UUID().uuidString
        let args: [String: JSONValue] = request.map { ["request": $0] } ?? [:]
        let envelope = try GatewayRequest(
            rpcId: rpcId, namespace: "session", method: method, args: args
        )
        let data = try await transport.request(
            path: envelope.path, body: JSONEncoder().encode(envelope)
        )
        return try GatewayResponse.value(from: data, expectedRpcId: rpcId)
    }

    func sessions() async throws -> [RemoteSession] {
        let value = try await call("list", request: .object([:]))
        return value.fields["items"]?.items.compactMap(RemoteSession.init) ?? []
    }

    func create(title: String, cwd: String, mode: String) async throws -> String {
        var fields: [String: JSONValue] = ["agentPreset": .string(mode)]
        if !cwd.isEmpty { fields["cwd"] = .string(cwd) }
        let created = try await call("create", request: .object(fields))
        guard let id = created.fields["sessionId"]?.text else {
            throw GatewayError.invalidEnvelope
        }
        if !title.isEmpty {
            _ = try await call("rename", request: .object([
                "sessionId": .string(id), "title": .string(title),
            ]))
        }
        return id
    }

    func prompt(sessionId: String, text: String) async throws {
        _ = try await call("prompt", request: .object([
            "requestId": .string(UUID().uuidString),
            "sessionId": .string(sessionId),
            "mode": .string("queue"),
            "content": .array([.object([
                "type": .string("text"), "text": .string(text),
            ])]),
            "clientTimeZone": .string(TimeZone.current.identifier),
        ]))
    }

    func cancel(sessionId: String) async throws {
        _ = try await call("cancel", request: .object([
            "sessionId": .string(sessionId),
        ]))
    }

    func relayState() async throws -> JSONValue {
        let data = try await transport.request(
            path: "/dsh-tether/relay", method: "GET",
            headers: ["x-dsh-tether-control": "1"]
        )
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func follow(sessionId: String) async throws -> AsyncThrowingStream<JSONValue, Error> {
        let socket = try await transport.openWebSocket()
        let streamId = UUID().uuidString
        let address: JSONValue = .object([
            "kind": .string("session"),
            "sessionId": .string(sessionId),
        ])
        try await socket.sendJSON(.object([
            "type": .string("open"),
            "streamId": .string(streamId),
            "endpoint": .string("session/follow"),
            "payload": .object(["args": .object([
                "request": .object([
                    "address": address,
                    "maxMessages": .number(100),
                ]),
            ])]),
        ]))
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let frame = try await socket.nextJSON().fields
                        guard frame["streamId"]?.text == streamId else { continue }
                        switch frame["type"]?.text {
                        case "item":
                            if let value = frame["value"] { continuation.yield(value) }
                        case "end":
                            continuation.finish()
                            return
                        case "error":
                            let reason = frame["error"]?.fields["message"]?.text
                                ?? "会话流断开"
                            throw NSError(domain: "DSHGateway", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: reason])
                        default: continue
                        }
                    }
                } catch {
                    if !Task.isCancelled { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await socket.close() }
            }
        }
    }
}
