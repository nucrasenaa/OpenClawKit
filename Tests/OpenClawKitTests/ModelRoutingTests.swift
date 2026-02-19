import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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

    struct ThrowingProvider: ModelProvider {
        let id: String
        let message: String

        func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
            _ = request
            throw OpenClawCoreError.unavailable(self.message)
        }
    }

    struct StreamingProvider: ModelProvider {
        let id: String

        func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
            _ = request
            return ModelGenerationResponse(text: "stream-final", providerID: self.id, modelID: "stream")
        }

        func generateStream(_ request: ModelGenerationRequest) async -> AsyncThrowingStream<ModelStreamChunk, Error> {
            _ = request
            return AsyncThrowingStream { continuation in
                continuation.yield(ModelStreamChunk(text: "stream-", isFinal: false))
                continuation.yield(ModelStreamChunk(text: "final", isFinal: true))
                continuation.finish()
            }
        }
    }

    actor MockOpenAICompatibleTransport: OpenAICompatibleHTTPTransport {
        let statusCode: Int
        let body: Data
        private(set) var lastPath: String?

        init(statusCode: Int = 200, body: Data) {
            self.statusCode = statusCode
            self.body = body
        }

        func data(for request: URLRequest) async throws -> HTTPResponseData {
            self.lastPath = request.url?.path
            return HTTPResponseData(statusCode: self.statusCode, headers: [:], body: self.body)
        }

        func path() -> String? {
            self.lastPath
        }
    }

    actor MockAnthropicTransport: AnthropicHTTPTransport {
        let statusCode: Int
        let body: Data

        init(statusCode: Int = 200, body: Data) {
            self.statusCode = statusCode
            self.body = body
        }

        func data(for request: URLRequest) async throws -> HTTPResponseData {
            _ = request
            return HTTPResponseData(statusCode: self.statusCode, headers: [:], body: self.body)
        }
    }

    actor MockGeminiTransport: GeminiHTTPTransport {
        let statusCode: Int
        let body: Data
        private(set) var lastQuery: String?

        init(statusCode: Int = 200, body: Data) {
            self.statusCode = statusCode
            self.body = body
        }

        func data(for request: URLRequest) async throws -> HTTPResponseData {
            self.lastQuery = request.url?.query
            return HTTPResponseData(statusCode: self.statusCode, headers: [:], body: self.body)
        }

        func query() -> String? {
            self.lastQuery
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

    @Test
    func routerUsesMetadataFallbackWhenRequestedProviderMissing() async throws {
        let router = ModelRouter()
        await router.register(StaticProvider(id: "secondary", text: "secondary-output"))

        let response = try await router.generate(
            ModelGenerationRequest(
                sessionKey: "main",
                prompt: "hello",
                providerID: "does-not-exist",
                metadata: ["fallbackProviderID": "secondary"]
            )
        )
        #expect(response.providerID == "secondary")
        #expect(response.text == "secondary-output")
    }

    @Test
    func routerFallsBackToNextProviderWhenPrimaryThrows() async throws {
        let router = ModelRouter(defaultProviderID: "fallback", providers: [
            ThrowingProvider(id: "primary", message: "primary failed"),
            StaticProvider(id: "fallback", text: "fallback-output"),
        ])

        let response = try await router.generate(
            ModelGenerationRequest(
                sessionKey: "main",
                prompt: "hello",
                providerID: "primary"
            )
        )

        #expect(response.providerID == "fallback")
        #expect(response.text == "fallback-output")
    }

    @Test
    func routerUsesOrderedPolicyFallbackChain() async throws {
        let router = ModelRouter(defaultProviderID: "echo", providers: [
            ThrowingProvider(id: "primary", message: "primary failed"),
            ThrowingProvider(id: "secondary", message: "secondary failed"),
            StaticProvider(id: "tertiary", text: "tertiary-output"),
            EchoModelProvider(),
        ])

        let response = try await router.generate(
            ModelGenerationRequest(
                sessionKey: "main",
                prompt: "hello",
                providerID: "primary",
                policy: ModelGenerationPolicy(
                    fallbackProviderIDs: ["secondary", "tertiary"]
                )
            )
        )

        #expect(response.providerID == "tertiary")
        #expect(response.text == "tertiary-output")
    }

    @Test
    func routerGenerateStreamUsesStreamingProviderWhenAvailable() async throws {
        let router = ModelRouter(defaultProviderID: "streamer", providers: [
            StreamingProvider(id: "streamer"),
        ])

        let stream = await router.generateStream(
            ModelGenerationRequest(sessionKey: "main", prompt: "hello", providerID: "streamer")
        )
        var chunks: [ModelStreamChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        #expect(chunks.count == 2)
        #expect(chunks.map(\.text).joined() == "stream-final")
        #expect(chunks.last?.isFinal == true)
    }

    @Test
    func openAICompatibleProviderParsesChatCompletionResponse() async throws {
        let transport = MockOpenAICompatibleTransport(
            body: Data("""
            {"model":"gpt-4.1-mini","choices":[{"index":0,"message":{"role":"assistant","content":"compat-output"}}]}
            """.utf8)
        )
        let provider = OpenAICompatibleModelProvider(
            configuration: OpenAICompatibleModelConfig(
                enabled: true,
                modelID: "gpt-4.1-mini",
                apiKey: "key",
                baseURL: "https://compat.example/v1",
                chatCompletionsPath: "chat/completions"
            ),
            transport: transport
        )
        let response = try await provider.generate(
            ModelGenerationRequest(sessionKey: "s1", prompt: "hello")
        )

        #expect(response.providerID == OpenAICompatibleModelProvider.providerID)
        #expect(response.text == "compat-output")
        #expect(await transport.path()?.contains("/v1/chat/completions") == true)
    }

    @Test
    func anthropicProviderParsesMessagesResponse() async throws {
        let transport = MockAnthropicTransport(
            body: Data("""
            {"id":"msg_1","model":"claude-3-5-haiku-latest","content":[{"type":"text","text":"anthropic-output"}]}
            """.utf8)
        )
        let provider = AnthropicModelProvider(
            configuration: AnthropicModelConfig(
                enabled: true,
                modelID: "claude-3-5-haiku-latest",
                apiKey: "key"
            ),
            transport: transport
        )
        let response = try await provider.generate(
            ModelGenerationRequest(sessionKey: "s1", prompt: "hello")
        )

        #expect(response.providerID == AnthropicModelProvider.providerID)
        #expect(response.text == "anthropic-output")
    }

    @Test
    func geminiProviderParsesGenerateContentResponse() async throws {
        let transport = MockGeminiTransport(
            body: Data("""
            {"candidates":[{"content":{"parts":[{"text":"gemini-output"}]}}]}
            """.utf8)
        )
        let provider = GeminiModelProvider(
            configuration: GeminiModelConfig(
                enabled: true,
                modelID: "gemini-2.0-flash",
                apiKey: "gem-key",
                baseURL: "https://generativelanguage.googleapis.com/v1beta"
            ),
            transport: transport
        )
        let response = try await provider.generate(
            ModelGenerationRequest(sessionKey: "s1", prompt: "hello")
        )

        #expect(response.providerID == GeminiModelProvider.providerID)
        #expect(response.text == "gemini-output")
        #expect(await transport.query()?.contains("key=gem-key") == true)
    }
}
