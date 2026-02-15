import Foundation
import Testing
@testable import OpenClawProtocol

@Suite("Protocol models")
struct ProtocolModelsTests {
    @Test
    func protocolVersionAndErrorCodesAreStable() {
        #expect(GATEWAY_PROTOCOL_VERSION == 3)
        #expect(ErrorCode.notLinked.rawValue == "NOT_LINKED")
        #expect(ErrorCode.unavailable.rawValue == "UNAVAILABLE")
    }

    @Test
    func requestFrameRoundTrip() throws {
        let frame = RequestFrame(
            type: "req",
            id: "abc",
            method: "agent.run",
            params: AnyCodable(["prompt": AnyCodable("hello")])
        )

        let encoded = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(RequestFrame.self, from: encoded)

        #expect(decoded.type == "req")
        #expect(decoded.id == "abc")
        #expect(decoded.method == "agent.run")
    }

    @Test
    func gatewayFrameEncodeDecode() throws {
        let response = ResponseFrame(
            type: "res",
            id: "r1",
            ok: true,
            payload: AnyCodable(["status": AnyCodable("accepted")]),
            error: nil
        )
        let frame = GatewayFrame.res(response)

        let encoded = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(GatewayFrame.self, from: encoded)

        switch decoded {
        case .res(let payload):
            #expect(payload.ok == true)
            #expect(payload.id == "r1")
        default:
            Issue.record("Expected .res frame")
        }
    }
}

