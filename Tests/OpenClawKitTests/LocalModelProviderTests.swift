import Testing
@testable import OpenClawKit

@Suite("Local model provider")
struct LocalModelProviderTests {
    actor RecordingEngine: LocalModelEngine {
        var loaded = false
        var loadCount = 0
        var prompts: [String] = []
        let response: String

        init(response: String) {
            self.response = response
        }

        func loadModel(path _: String, configuration _: LocalModelConfig) async throws {
            self.loaded = true
            self.loadCount += 1
        }

        func unloadModel() async {
            self.loaded = false
        }

        func isModelLoaded() async -> Bool {
            self.loaded
        }

        func generate(
            prompt: String,
            systemPrompt _: String?,
            configuration _: LocalModelConfig,
            onToken: (@Sendable (String) -> Bool)?
        ) async throws -> String {
            self.prompts.append(prompt)
            if let onToken {
                _ = onToken(self.response)
            }
            return self.response
        }

        func snapshot() -> (Bool, Int, [String]) {
            (self.loaded, self.loadCount, self.prompts)
        }
    }

    @Test
    func throwsWhenLocalProviderDisabled() async throws {
        let engine = RecordingEngine(response: "n/a")
        let provider = LocalModelProvider(
            configuration: LocalModelConfig(enabled: false, modelPath: "/tmp/model.gguf"),
            engine: engine
        )

        do {
            _ = try await provider.generate(
                ModelGenerationRequest(sessionKey: "main", prompt: "hello")
            )
            Issue.record("Expected disabled local provider error")
        } catch {
            #expect(String(describing: error).lowercased().contains("disabled"))
        }
    }

    @Test
    func loadsModelAndReturnsGeneratedText() async throws {
        let engine = RecordingEngine(response: "local response")
        let provider = LocalModelProvider(
            configuration: LocalModelConfig(enabled: true, modelPath: "/tmp/model.gguf"),
            engine: engine
        )

        let first = try await provider.generate(
            ModelGenerationRequest(sessionKey: "main", prompt: "first")
        )
        let second = try await provider.generate(
            ModelGenerationRequest(sessionKey: "main", prompt: "second")
        )
        let (loaded, loadCount, prompts) = await engine.snapshot()

        #expect(first.text == "local response")
        #expect(second.text == "local response")
        #expect(first.providerID == LocalModelProvider.providerID)
        #expect(loaded)
        #expect(loadCount == 1)
        #expect(prompts == ["first", "second"])
    }
}
