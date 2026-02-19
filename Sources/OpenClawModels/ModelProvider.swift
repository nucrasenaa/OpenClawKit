import Foundation
import OpenClawCore
import OpenClawProtocol

/// Runtime generation policy used for model-provider selection and behavior controls.
public struct ModelGenerationPolicy: Sendable, Equatable {
    /// Requests token streaming when provider supports it.
    public let streamTokens: Bool
    /// Indicates whether runtime cancellation should be honored.
    public let allowCancellation: Bool
    /// Optional caller-provided cancellation token identifier.
    public let cancellationToken: String?
    /// Optional max token override.
    public let maxTokens: Int?
    /// Optional sampling temperature override.
    public let temperature: Double?
    /// Optional top-p override.
    public let topP: Double?
    /// Optional top-k override.
    public let topK: Int?
    /// Optional request timeout override in milliseconds.
    public let requestTimeoutMs: Int?
    /// Ordered provider fallback identifiers attempted after primary provider.
    public let fallbackProviderIDs: [String]
    /// Optional local-runtime-specific hints (for example hardware/backend toggles).
    public let localRuntimeHints: [String: String]

    /// Creates generation policy values.
    /// - Parameters:
    ///   - streamTokens: Requests streaming behavior.
    ///   - allowCancellation: Enables cancellation support for this request.
    ///   - cancellationToken: Optional cancellation token.
    ///   - maxTokens: Optional max token override.
    ///   - temperature: Optional temperature override.
    ///   - topP: Optional top-p override.
    ///   - topK: Optional top-k override.
    ///   - requestTimeoutMs: Optional timeout override in milliseconds.
    ///   - fallbackProviderIDs: Ordered provider fallback chain.
    ///   - localRuntimeHints: Optional local runtime hints.
    public init(
        streamTokens: Bool = false,
        allowCancellation: Bool = true,
        cancellationToken: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        requestTimeoutMs: Int? = nil,
        fallbackProviderIDs: [String] = [],
        localRuntimeHints: [String: String] = [:]
    ) {
        self.streamTokens = streamTokens
        self.allowCancellation = allowCancellation
        self.cancellationToken = cancellationToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maxTokens = maxTokens.map { max(1, $0) }
        self.temperature = temperature
        self.topP = topP
        self.topK = topK.map { max(1, $0) }
        self.requestTimeoutMs = requestTimeoutMs.map { max(1, $0) }
        self.fallbackProviderIDs = fallbackProviderIDs
        self.localRuntimeHints = localRuntimeHints
    }
}

/// Input payload passed to model providers.
public struct ModelGenerationRequest: Sendable, Equatable {
    /// Session key associated with generation request.
    public let sessionKey: String
    /// User prompt payload.
    public let prompt: String
    /// Optional system prompt prefix.
    public let systemPrompt: String?
    /// Optional explicit provider override.
    public let providerID: String?
    /// Additional provider-specific metadata.
    public let metadata: [String: String]
    /// Runtime generation policy controls.
    public let policy: ModelGenerationPolicy

    /// Creates a model generation request.
    /// - Parameters:
    ///   - sessionKey: Session key.
    ///   - prompt: Prompt payload.
    ///   - systemPrompt: Optional system prompt.
    ///   - providerID: Optional provider override.
    ///   - metadata: Additional metadata.
    ///   - policy: Runtime generation policy controls.
    public init(
        sessionKey: String,
        prompt: String,
        systemPrompt: String? = nil,
        providerID: String? = nil,
        metadata: [String: String] = [:],
        policy: ModelGenerationPolicy = ModelGenerationPolicy()
    ) {
        self.sessionKey = sessionKey
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.metadata = metadata
        self.policy = policy
    }
}

/// Output payload returned from model providers.
public struct ModelGenerationResponse: Sendable, Equatable {
    /// Generated text output.
    public let text: String
    /// Provider identifier that generated the output.
    public let providerID: String
    /// Optional concrete model identifier.
    public let modelID: String?

    /// Creates a model generation response.
    /// - Parameters:
    ///   - text: Generated text output.
    ///   - providerID: Provider identifier.
    ///   - modelID: Optional concrete model identifier.
    public init(text: String, providerID: String, modelID: String? = nil) {
        self.text = text
        self.providerID = providerID
        self.modelID = modelID
    }
}

/// Streaming chunk payload emitted by providers that support token streaming.
public struct ModelStreamChunk: Sendable, Equatable {
    /// Token/text fragment.
    public let text: String
    /// Indicates whether this chunk marks end-of-stream payload.
    public let isFinal: Bool

    /// Creates a streaming chunk.
    /// - Parameters:
    ///   - text: Token/text fragment.
    ///   - isFinal: End-of-stream marker.
    public init(text: String, isFinal: Bool = false) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// Interface implemented by model backends.
public protocol ModelProvider: Sendable {
    /// Stable provider identifier.
    var id: String { get }
    /// Executes generation request.
    /// - Parameter request: Generation request payload.
    /// - Returns: Generation response payload.
    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse

    /// Returns a token stream for providers that support streaming generation.
    /// - Parameter request: Generation request payload.
    /// - Returns: Async throwing stream of model chunks.
    func generateStream(_ request: ModelGenerationRequest) -> AsyncThrowingStream<ModelStreamChunk, Error>
}

public extension ModelProvider {
    /// Default streaming implementation for non-streaming providers.
    /// - Parameter request: Generation request payload.
    /// - Returns: Stream with a single final chunk containing full generated text.
    func generateStream(_ request: ModelGenerationRequest) -> AsyncThrowingStream<ModelStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await self.generate(request)
                    continuation.yield(ModelStreamChunk(text: response.text, isFinal: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Default fallback provider returning deterministic placeholder output.
public struct EchoModelProvider: ModelProvider {
    /// Default echo provider identifier.
    public static let defaultID = "echo"
    /// Provider identifier.
    public let id: String

    /// Creates an echo provider.
    /// - Parameter id: Provider identifier.
    public init(id: String = EchoModelProvider.defaultID) {
        self.id = id
    }

    /// Returns a deterministic echo response.
    /// - Parameter request: Generation request payload.
    /// - Returns: Echo response.
    public func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
        _ = request
        return ModelGenerationResponse(text: "OK", providerID: self.id, modelID: "echo-1")
    }
}

/// Actor that resolves providers and routes generation requests.
public actor ModelRouter {
    private var providers: [String: any ModelProvider]
    private var defaultProviderID: String

    /// Creates a model router.
    /// - Parameters:
    ///   - defaultProviderID: Default provider identifier.
    ///   - providers: Initial provider list.
    public init(
        defaultProviderID: String = EchoModelProvider.defaultID,
        providers: [any ModelProvider] = [EchoModelProvider()]
    ) {
        var map: [String: any ModelProvider] = [:]
        for provider in providers {
            map[provider.id] = provider
        }
        if map[defaultProviderID] == nil {
            map[EchoModelProvider.defaultID] = EchoModelProvider()
            self.defaultProviderID = EchoModelProvider.defaultID
        } else {
            self.defaultProviderID = defaultProviderID
        }
        self.providers = map
    }

    /// Registers or replaces a provider.
    /// - Parameter provider: Provider implementation.
    public func register(_ provider: any ModelProvider) {
        self.providers[provider.id] = provider
    }

    /// Sets default provider by identifier.
    /// - Parameter id: Provider identifier.
    public func setDefaultProviderID(_ id: String) throws {
        guard self.providers[id] != nil else {
            throw OpenClawCoreError.invalidConfiguration("Unknown model provider: \(id)")
        }
        self.defaultProviderID = id
    }

    /// Returns configured provider identifiers sorted alphabetically.
    public func configuredProviderIDs() -> [String] {
        self.providers.keys.sorted()
    }

    /// Routes generation request to requested/default provider.
    /// - Parameter request: Generation request payload.
    /// - Returns: Provider response.
    public func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
        let orderedProviderIDs = self.resolveProviderOrder(for: request)
        var lastError: Error?
        for providerID in orderedProviderIDs {
            guard let provider = self.providers[providerID] else {
                continue
            }
            do {
                return try await provider.generate(request)
            } catch {
                lastError = error
            }
        }
        if let lastError {
            throw lastError
        }
        throw OpenClawCoreError.invalidConfiguration(
            "No registered model providers available for request and fallback chain"
        )
    }

    /// Returns a token stream from the first available provider in fallback order.
    /// - Parameter request: Generation request payload.
    /// - Returns: Async throwing stream of model chunks.
    public func generateStream(_ request: ModelGenerationRequest) -> AsyncThrowingStream<ModelStreamChunk, Error> {
        let orderedProviderIDs = self.resolveProviderOrder(for: request)
        for providerID in orderedProviderIDs {
            if let provider = self.providers[providerID] {
                return provider.generateStream(request)
            }
        }
        return AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: OpenClawCoreError.invalidConfiguration(
                    "No registered model providers available for streaming request"
                )
            )
        }
    }

    private func resolveProviderOrder(for request: ModelGenerationRequest) -> [String] {
        var orderedIDs: [String] = []
        var seen: Set<String> = []

        func appendProviderID(_ rawID: String?) {
            guard let rawID else { return }
            let normalized = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            if seen.insert(normalized).inserted {
                orderedIDs.append(normalized)
            }
        }

        func appendProviderList(_ rawList: String?) {
            guard let rawList else { return }
            let components = rawList.split { character in
                character == "," || character == ";"
            }
            for component in components {
                appendProviderID(String(component))
            }
        }

        appendProviderID(request.providerID)
        for fallbackID in request.policy.fallbackProviderIDs {
            appendProviderID(fallbackID)
        }
        appendProviderList(request.metadata["fallbackProviderID"])
        appendProviderList(request.metadata["fallbackProviderIDs"])
        appendProviderID(self.defaultProviderID)
        return orderedIDs
    }
}
