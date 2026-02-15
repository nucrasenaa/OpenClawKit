import Foundation
import Testing
@testable import OpenClawKit

@Test func sdkExposesProtocolVersion() async throws {
    let sdk = OpenClawSDK.shared
    #expect(sdk.buildInfo.protocolVersion == GATEWAY_PROTOCOL_VERSION)
}

@Test func gatewayClientConnectLifecycle() async throws {
    let client = GatewayClient()
    #expect(await client.isConnected() == false)

    try await client.connect(to: GatewayEndpoint(url: URL(string: "ws://127.0.0.1:18789")!))
    #expect(await client.isConnected() == true)

    await client.disconnect()
    #expect(await client.isConnected() == false)
}
