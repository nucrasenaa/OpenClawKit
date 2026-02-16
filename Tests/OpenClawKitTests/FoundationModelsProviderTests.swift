import Testing
@testable import OpenClawKit

@Suite("Foundation Models provider")
struct FoundationModelsProviderTests {
    @Test
    func providerThrowsUnavailableWhenFrameworkOrOSIsMissing() async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            return
        }
        #endif

        let provider = FoundationModelsProvider()
        do {
            _ = try await provider.generate(
                ModelGenerationRequest(sessionKey: "main", prompt: "hello")
            )
            Issue.record("Expected Foundation Models to be unavailable")
        } catch {
            #expect(String(describing: error).lowercased().contains("foundation"))
        }
    }

    @Test
    func routerFallsBackToDefaultProviderWhenRequestedProviderIsMissing() async throws {
        let router = ModelRouter()
        let response = try await router.generate(
            ModelGenerationRequest(
                sessionKey: "main",
                prompt: "hello",
                providerID: FoundationModelsProvider.providerID
            )
        )

        #expect(response.providerID == EchoModelProvider.defaultID)
        #expect(response.text == "OK")
    }
}
