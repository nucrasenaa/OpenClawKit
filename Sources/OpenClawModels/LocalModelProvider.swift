import Foundation
import OpenClawCore

public protocol LocalModelEngine: Sendable {
    func loadModel(path: String, configuration: LocalModelConfig) async throws
    func unloadModel() async
    func isModelLoaded() async -> Bool
    func generate(
        prompt: String,
        systemPrompt: String?,
        configuration: LocalModelConfig,
        onToken: (@Sendable (String) -> Bool)?
    ) async throws -> String
}

public actor LocalModelProvider: ModelProvider {
    public static let providerID = "local"
    public let id: String

    private let engine: any LocalModelEngine
    private let configuration: LocalModelConfig

    public init(
        id: String = LocalModelProvider.providerID,
        configuration: LocalModelConfig,
        engine: any LocalModelEngine
    ) {
        self.id = id
        self.configuration = configuration
        self.engine = engine
    }

    public func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
        guard self.configuration.enabled else {
            throw OpenClawCoreError.unavailable("Local model provider is disabled")
        }
        guard let modelPath = self.configuration.modelPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelPath.isEmpty
        else {
            throw OpenClawCoreError.invalidConfiguration("Local model path is required")
        }

        if await self.engine.isModelLoaded() == false {
            try await self.engine.loadModel(path: modelPath, configuration: self.configuration)
        }

        let output = try await self.engine.generate(
            prompt: request.prompt,
            systemPrompt: request.systemPrompt,
            configuration: self.configuration,
            onToken: nil
        )
        return ModelGenerationResponse(
            text: output,
            providerID: self.id,
            modelID: URL(fileURLWithPath: modelPath).lastPathComponent
        )
    }

    public func unload() async {
        await self.engine.unloadModel()
    }
}

public actor StubLocalModelEngine: LocalModelEngine {
    private var loaded = false
    private let cannedResponse: String

    public init(cannedResponse: String = "local-ok") {
        self.cannedResponse = cannedResponse
    }

    public func loadModel(path _: String, configuration _: LocalModelConfig) async throws {
        self.loaded = true
    }

    public func unloadModel() async {
        self.loaded = false
    }

    public func isModelLoaded() async -> Bool {
        self.loaded
    }

    public func generate(
        prompt _: String,
        systemPrompt _: String?,
        configuration _: LocalModelConfig,
        onToken: (@Sendable (String) -> Bool)?
    ) async throws -> String {
        if let onToken {
            _ = onToken(self.cannedResponse)
        }
        return self.cannedResponse
    }
}
