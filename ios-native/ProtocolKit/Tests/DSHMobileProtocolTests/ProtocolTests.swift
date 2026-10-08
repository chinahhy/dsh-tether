import Foundation
import XCTest
@testable import DSHMobileProtocol

final class ProtocolTests: XCTestCase {
    func testWireUsesHostTagsAndSnakeCaseFields() throws {
        let messages: [TetherWire] = [
            .hello(name: "iPhone"), .pair(code: "123456", name: "iPhone"), .proxy,
            .pairOK, .pairFail(reason: "bad-code"),
            .approval(id: "a", toolName: "Shell", reason: "check"),
            .approvalCancel(id: "a"), .decision(id: "a", outcome: "allow"),
        ]
        for message in messages {
            let line = try TetherWireCodec.encode(message)
            XCTAssertEqual(line.last, 10)
            XCTAssertEqual(try TetherWireCodec.decode(Data(line.dropLast())), message)
        }
        let approval = try TetherWireCodec.encode(.approval(id: "a", toolName: "Shell", reason: "check"))
        XCTAssertTrue(String(decoding: approval, as: UTF8.self).contains("\"tool_name\""))
    }

    func testBoundedFragmentedLineAndUnknownType() throws {
        var buffer = WireLineBuffer(unpaired: true)
        XCTAssertEqual(try buffer.append(Data(#"{"type":"pair","code":"123456","name":"iPhone"}"#.utf8)), [])
        XCTAssertEqual(try buffer.append(Data([10])), [.pair(code: "123456", name: "iPhone")])
        XCTAssertThrowsError(try TetherWireCodec.decode(Data(repeating: 65, count: 513), unpaired: true)) {
            XCTAssertEqual($0 as? WireError, .oversizedLine)
        }
        XCTAssertThrowsError(try TetherWireCodec.decode(Data(#"{"type":"future"}"#.utf8))) {
            XCTAssertEqual($0 as? WireError, .unknownType)
        }
    }

    func testGatewayRequestAndResponseCorrelation() throws {
        let request = try GatewayRequest(rpcId: "r-1", namespace: "session", method: "list", args: [:])
        XCTAssertEqual(request.path, "/api/session/list")
        let encoded = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(body["type"] as? String, "client-request")
        XCTAssertEqual(body["rpcId"] as? String, "r-1")
        let ok = Data(#"{"type":"server-response","rpcId":"r-1","result":{"ok":true,"value":{"items":[]}}}"#.utf8)
        XCTAssertEqual(try GatewayResponse.value(from: ok, expectedRpcId: "r-1"), .object(["items": .array([])]))
        XCTAssertThrowsError(try GatewayResponse.value(from: ok, expectedRpcId: "other")) {
            XCTAssertEqual($0 as? GatewayError, .rpcIdMismatch)
        }
        let failure = Data(#"{"type":"server-response","rpcId":"r-1","result":{"ok":false,"error":{"code":"denied","message":"no","details":{}}}}"#.utf8)
        XCTAssertThrowsError(try GatewayResponse.value(from: failure, expectedRpcId: "r-1")) {
            XCTAssertEqual($0 as? GatewayError, .remote(code: "denied", message: "no"))
        }
    }

    func testGatewayRejectsPathInjection() {
        XCTAssertThrowsError(try GatewayRequest(rpcId: "r", namespace: "session", method: "../list", args: [:]))
    }
}
