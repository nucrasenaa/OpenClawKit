import Testing
@testable import OpenClawKit

@Suite("Model routing")
struct ModelRoutingTests {
    struct StaticProvider: ModelProvider {
        let id: String
        let text: String

        func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
            _ = request
            return ModelGenerationResponse(text: self.text, providerID: self.id, modelID: "static")
        }
    }

    @Test
    func routerUsesDefaultProviderWhenRequestDoesNotSpecifyOne() async throws {
        let router = ModelRouter()
        let response = try await router.generate(
            ModelGenerationRequest(sessionKey: "main", prompt: "hello")
        )

        #expect(response.providerID == EchoModelProvider.defaultID)
        #expect(response.text == "OK")
    }

    @Test
    func routerSupportsRegisteredProviderAsDefault() async throws {
        let router = ModelRouter()
        await router.register(StaticProvider(id: "custom", text: "custom-output"))
        try await router.setDefaultProviderID("custom")

        let response = try await router.generate(
            ModelGenerationRequest(sessionKey: "main", prompt: "hello")
        )
        #expect(response.providerID == "custom")
        #expect(response.text == "custom-output")
    }

    @Test
    func runtimeUsesExplicitProviderFromRunRequest() async throws {
        let router = ModelRouter()
        await router.register(StaticProvider(id: "discord", text: "agent-response"))
        let runtime = EmbeddedAgentRuntime(modelRouter: router)

        let result = try await runtime.run(
            AgentRunRequest(
                sessionKey: "main",
                prompt: "hi",
                modelProviderID: "discord"
            )
        )

        #expect(result.output == "agent-response")
    }
}
