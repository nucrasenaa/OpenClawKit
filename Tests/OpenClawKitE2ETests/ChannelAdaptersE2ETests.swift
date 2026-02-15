import Foundation
import Testing
@testable import OpenClawKit

@Suite("Channel adapters E2E")
struct ChannelAdaptersE2ETests {
    @Test
    func supportsCoreChannelIDs() async throws {
        let registry = ChannelRegistry()
        for channelID in ChannelID.allCases {
            await registry.register(InMemoryChannelAdapter(id: channelID))
        }

        let ids = await registry.adapterIDs().map(\.rawValue)
        #expect(ids.contains("whatsapp"))
        #expect(ids.contains("telegram"))
        #expect(ids.contains("slack"))
        #expect(ids.contains("discord"))
        #expect(ids.contains("signal"))
        #expect(ids.contains("imessage"))
        #expect(ids.contains("line"))
    }
}

