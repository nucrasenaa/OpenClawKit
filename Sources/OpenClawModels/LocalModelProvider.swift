import Foundation
import OpenClawCore

/// Runtime contract for loading and querying a local model engine.
public protocol LocalModelEngine: Sendable {
    /// Loads model resources.
    /// - Parameters:
    ///   - path: Model path.
    ///   - configuration: Local model configuration.
    func loadModel(path: String, configuration: LocalModelConfig) async throws
    /// Unloads model resources.
    func unloadModel() async
    /// Returns whether model resources are currently loaded.
    func isModelLoaded() async -> Bool
    /// Generates text output and optionally streams tokens.
    /// - Parameters:
    ///   - prompt: Prompt payload.
    ///   - systemPrompt: Optional system prompt.
    ///   - configuration: Local model configuration.
    ///   - onToken: Optional streaming token callback.
    /// - Returns: Final generated output text.
    func generate(
        prompt: String,
        systemPrompt: String?,
        configuration: LocalModelConfig,
        onToken: (@Sendable (String) -> Bool)?
    ) async throws -> String
}

/// Model provider that routes generation calls to a local model engine.
public actor LocalModelProvider: ModelProvider {
    /// Canonical provider identifier.
    public static let providerID = "local"
    /// Provider identifier.
    public let id: String

    private let engine: any LocalModelEngine
    private let configuration: LocalModelConfig

    /// Creates a local model provider.
    /// - Parameters:
    ///   - id: Provider identifier.
    ///   - configuration: Local model configuration.
    ///   - engine: Local model engine implementation.
    public init(
        id: String = LocalModelProvider.providerID,
        configuration: LocalModelConfig,
        engine: any LocalModelEngine
    ) {
        self.id = id
        self.configuration = configuration
        self.engine = engine
    }

    /// Generates text using the local model runtime.
    /// - Parameter request: Generation request payload.
    /// - Returns: Generation response payload.
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

    /// Unloads the underlying model engine.
    public func unload() async {
        await self.engine.unloadModel()
    }
}

/// Test-friendly local model engine that returns deterministic output.
public actor StubLocalModelEngine: LocalModelEngine {
    private var loaded = false
    private let cannedResponse: String

    /// Creates a stub engine.
    /// - Parameter cannedResponse: Response returned for generation calls.
    public init(cannedResponse: String = "local-ok") {
        self.cannedResponse = cannedResponse
    }

    /// Marks model as loaded.
    public func loadModel(path _: String, configuration _: LocalModelConfig) async throws {
        self.loaded = true
    }

    /// Marks model as unloaded.
    public func unloadModel() async {
        self.loaded = false
    }

    /// Returns current loaded state.
    public func isModelLoaded() async -> Bool {
        self.loaded
    }

    /// Returns deterministic output and forwards it to optional token callback.
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
