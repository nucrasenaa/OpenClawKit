import Foundation
import Testing
@testable import OpenClawKit

@Suite("Local model provider")
struct LocalModelProviderTests {
    actor RecordingEngine: LocalModelEngine {
        var loaded = false
        var loadCount = 0
        var prompts: [String] = []
        let response: String
        let tokenChunks: [String]
        private(set) var runtimeTransitions: [(String?, String)] = []
        private(set) var cancelledTokens: [String?] = []
        private(set) var restoredStates: [String] = []

        init(response: String, tokenChunks: [String]? = nil) {
            self.response = response
            self.tokenChunks = tokenChunks ?? [response]
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
            var emitted = ""
            for chunk in self.tokenChunks {
                if let onToken, onToken(chunk) == false {
                    return emitted
                }
                emitted += chunk
            }
            if let onToken {
                _ = onToken("")
            }
            return emitted.isEmpty ? self.response : emitted
        }

        func switchRuntime(from: String?, to: String, configuration _: LocalModelConfig) async throws {
            self.runtimeTransitions.append((from, to))
        }

        func cancelGeneration(token: String?) async {
            self.cancelledTokens.append(token)
        }

        func saveState() async throws -> Data? {
            guard let runtime = self.runtimeTransitions.last?.1 else { return nil }
            return Data(runtime.utf8)
        }

        func restoreState(_ state: Data) async throws {
            self.restoredStates.append(String(decoding: state, as: UTF8.self))
        }

        func snapshot() -> (
            loaded: Bool,
            loadCount: Int,
            prompts: [String],
            runtimeTransitions: [(String?, String)],
            cancelledTokens: [String?],
            restoredStates: [String]
        ) {
            (
                self.loaded,
                self.loadCount,
                self.prompts,
                self.runtimeTransitions,
                self.cancelledTokens,
                self.restoredStates
            )
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
        let snapshot = await engine.snapshot()

        #expect(first.text == "local response")
        #expect(second.text == "local response")
        #expect(first.providerID == LocalModelProvider.providerID)
        #expect(snapshot.loaded)
        #expect(snapshot.loadCount == 1)
        #expect(snapshot.prompts == ["first", "second"])
        #expect(snapshot.runtimeTransitions.count == 1)
        #expect(snapshot.runtimeTransitions.first?.1 == "llmfarm")
    }

    @Test
    func generateStreamEmitsChunksAndFinalMarker() async throws {
        let engine = RecordingEngine(response: "streamed", tokenChunks: ["stream", "ed"])
        let provider = LocalModelProvider(
            configuration: LocalModelConfig(enabled: true, modelPath: "/tmp/model.gguf", streamTokens: true),
            engine: engine
        )
        let request = ModelGenerationRequest(
            sessionKey: "main",
            prompt: "stream this",
            policy: ModelGenerationPolicy(streamTokens: true)
        )

        var chunks: [ModelStreamChunk] = []
        for try await chunk in await provider.generateStream(request) {
            chunks.append(chunk)
        }

        let nonFinal = chunks.filter { !$0.isFinal }
        #expect(nonFinal.map(\.text).joined() == "streamed")
        #expect(chunks.last?.isFinal == true)
    }

    @Test
    func supportsRuntimeSwitchCancellationAndStateRestore() async throws {
        let engine = RecordingEngine(response: "ok", tokenChunks: ["o", "k"])
        let provider = LocalModelProvider(
            configuration: LocalModelConfig(enabled: true, runtime: "llmfarm", modelPath: "/tmp/model.gguf"),
            engine: engine
        )

        _ = try await provider.generate(
            ModelGenerationRequest(sessionKey: "main", prompt: "first")
        )
        _ = try await provider.generate(
            ModelGenerationRequest(
                sessionKey: "main",
                prompt: "second",
                policy: ModelGenerationPolicy(
                    localRuntimeHints: ["runtime": "llmfarm-alt"]
                )
            )
        )

        await provider.cancelGeneration(token: "run-cancel")
        do {
            _ = try await provider.generate(
                ModelGenerationRequest(
                    sessionKey: "main",
                    prompt: "third",
                    policy: ModelGenerationPolicy(
                        allowCancellation: true,
                        cancellationToken: "run-cancel"
                    )
                )
            )
            Issue.record("Expected cancellation error")
        } catch {
            #expect(String(describing: error).lowercased().contains("cancel"))
        }

        let state = try await provider.saveRuntimeState()
        #expect(state != nil)
        if let state {
            try await provider.restoreRuntimeState(state)
        }

        let snapshot = await engine.snapshot()
        #expect(snapshot.runtimeTransitions.count == 2)
        #expect(snapshot.runtimeTransitions.last?.1 == "llmfarm-alt")
        #expect(snapshot.cancelledTokens.contains(where: { $0 == "run-cancel" }))
        #expect(snapshot.restoredStates.contains("llmfarm-alt"))
    }
}
