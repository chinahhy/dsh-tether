import Foundation

@main
struct ProtocolSmoke {
    static func main() throws {
        let approval = TetherWire.approval(id: "a-1", toolName: "Shell", reason: "check")
        let line = try TetherWireCodec.encode(approval)
        precondition(line.last == 10)
        precondition(String(decoding: line, as: UTF8.self).contains("\"tool_name\""))
        let decoded = try TetherWireCodec.decode(Data(line.dropLast()))
        precondition(decoded == approval)

        var buffer = WireLineBuffer(unpaired: true)
        let pair = Data(#"{"type":"pair","code":"123456","name":"iPhone"}"#.utf8)
        let partial = try buffer.append(pair)
        precondition(partial == [])
        let completed = try buffer.append(Data([10]))
        precondition(completed == [.pair(code: "123456", name: "iPhone")])
        do {
            _ = try TetherWireCodec.decode(Data(repeating: 65, count: 513), unpaired: true)
            fatalError("oversized unpaired line accepted")
        } catch WireError.oversizedLine {}

        let request = try GatewayRequest(rpcId: "r-1", namespace: "session", method: "list", args: [:])
        precondition(request.path == "/api/session/list")
        let response = Data(#"{"type":"server-response","rpcId":"r-1","result":{"ok":true,"value":{"items":[]}}}"#.utf8)
        let value = try GatewayResponse.value(from: response, expectedRpcId: "r-1")
        precondition(value == .object(["items": .array([])]))
        do {
            _ = try GatewayResponse.value(from: response, expectedRpcId: "wrong")
            fatalError("mismatched rpcId accepted")
        } catch GatewayError.rpcIdMismatch {}
        print("Protocol smoke checks passed")
    }
}
